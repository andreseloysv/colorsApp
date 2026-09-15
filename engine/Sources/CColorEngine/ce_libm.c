/*
 * ce_libm.c — libm portable y determinista del motor (fase 5; PLAN §5, ADR-003).
 *
 * cbrt, pow, exp, atan2, sin y cos copiados de musl 1.2.6 (la libm que Emscripten
 * compila a WASM; origen: emscripten 6.0.9, system/lib/libc/musl/src/math) y
 * renombrados ce_*. Este fichero se compila en TODAS las plataformas (SwiftPM,
 * CMake nativo y emcmake), así que el motor no depende de la libm del sistema
 * para ninguna función trascendente: solo usa +, −, ×, ÷, sqrt, floor y
 * manipulación de bits IEEE 754, todos exactos y con redondeo definido. Con
 * FP_CONTRACT OFF, Lab, ΔE00, pesos, scores y hashes salen bit a bit iguales
 * en Apple arm64/x86_64 y en WASM (verificado: `make parity`, `test_math`).
 *
 * Cambios respecto a musl (el resto es copia literal, tablas incluidas):
 *   - pow: los caminos `#if __FP_FAST_FMA` (que Apple clang activaría en arm64
 *     con __builtin_fma, redondeo distinto) quedan bajo CE_LIBM_USE_FMA = 0:
 *     siempre la versión sin FMA, que es la que ejecuta WASM;
 *   - double_t -> double (FLT_EVAL_METHOD == 0, comprobado con _Static_assert);
 *   - FORCE_EVAL / fp_force_eval (solo señalizan excepciones FP) eliminados:
 *     no cambian ningún valor devuelto;
 *   - funciones auxiliares (atan, __sin, __cos, __rem_pio2, __rem_pio2_large,
 *     scalbn, __math_*) static; macros de libm.h reescritas como CE_*;
 *   - la tabla ipio2 de __rem_pio2_large se incluye completa (sin el #if de
 *     LDBL_MAX_EXP) para que el fichero no dependa del long double del target.
 *
 * Ficheros de origen (sha256, 16 hex) en emscripten 6.0.9 / musl 1.2.6:
 *   cbrt.c               af442893d4048c0e
 *   atan.c               1cffb67a65456ae0
 *   atan2.c              a5f94b09b10b4e72
 *   __sin.c              f3a37ef9bcfb8a2f
 *   __cos.c              3f0f774aab60a18d
 *   scalbn.c             a2e766283ed30c2b
 *   __rem_pio2_large.c   b97f19fb5951c83a
 *   __rem_pio2.c         938329e0939cd83e
 *   sin.c                24e53a9d85f196f6
 *   cos.c                3a74e054057d636f
 *   exp_data.c           c55dff64e369fe81
 *   exp.c                7db56f21ca9b8915
 *   pow_data.c           2052ec913f9b4a21
 *   pow.c                b06f0a08d74fcff8
 *
 * Licencias: musl (MIT, Rich Felker et al.; ver system/lib/libc/musl/COPYRIGHT),
 * FreeBSD msun / SunPro (aviso conservado sobre cada función) y Arm Limited
 * (MIT, exp/pow/tablas de 2018). Comentarios originales en inglés.
 *
 * Reglas del motor: C11, sin I/O, sin malloc, sin estáticos mutables, sin RNG,
 * todo en double, sin contracción FMA.
 */
#include "ce/ce.h"

#include <float.h>
#include <math.h>
#include <stdint.h>

#pragma STDC FP_CONTRACT OFF

/* El código de musl asume evaluación en double sin precisión extra (nada de
 * x87): es así en arm64, x86_64 (SSE2) y wasm32. */
_Static_assert(FLT_EVAL_METHOD == 0, "ce_libm exige FLT_EVAL_METHOD == 0");
_Static_assert(sizeof(double) == 8 && DBL_MANT_DIG == 53, "ce_libm exige IEEE 754 binary64");

/* 0: nunca FMA (el camino que ejecuta WASM). No cambiar: rompería la paridad. */
#define CE_LIBM_USE_FMA 0

/* ---- equivalentes de musl src/internal/libm.h ---------------------------- */

#define CE_ASUINT64(f) ((union { double _f; uint64_t _i; }){f})._i
#define CE_ASDOUBLE(i) ((union { uint64_t _i; double _f; }){i})._f

#define CE_EXTRACT_WORDS(hi, lo, d)              \
    do {                                          \
        uint64_t ce_u_ = CE_ASUINT64(d);          \
        (hi) = (uint32_t)(ce_u_ >> 32);           \
        (lo) = (uint32_t)ce_u_;                   \
    } while (0)

#define CE_GET_HIGH_WORD(hi, d)                  \
    do {                                          \
        (hi) = (uint32_t)(CE_ASUINT64(d) >> 32);  \
    } while (0)

#ifdef __GNUC__
#define CE_PREDICT_TRUE(x) __builtin_expect(!!(x), 1)
#define CE_PREDICT_FALSE(x) __builtin_expect(x, 0)
#else
#define CE_PREDICT_TRUE(x) (x)
#define CE_PREDICT_FALSE(x) (x)
#endif

/* Con FLT_EVAL_METHOD == 0 una asignación ya evalúa en double. */
#define CE_EVAL_AS_DOUBLE(x) (x)

/* musl: WANT_ROUNDING 1 (redondeos no al más cercano también correctos),
 * WANT_SNAN 0 (sin NaN señalizantes). */
#define WANT_ROUNDING 1
#define CE_ISSIGNALING(x) 0

/* Devuelve su argumento impidiendo que el compilador lo reordene o lo
 * constant-folde (como fp_barrier de musl). */
static inline double ce_fp_barrier(double x)
{
    volatile double y = x;
    return y;
}

/* musl __math_xflow / __math_oflow / __math_uflow / __math_invalid. */
static double ce_math_xflow(uint32_t sign, double y)
{
    return CE_EVAL_AS_DOUBLE(ce_fp_barrier(sign ? -y : y) * y);
}

static double ce_math_oflow(uint32_t sign)
{
    return ce_math_xflow(sign, 0x1p769);
}

static double ce_math_uflow(uint32_t sign)
{
    return ce_math_xflow(sign, 0x1p-767);
}

static double ce_math_invalid(double x)
{
    return (x - x) / (x - x);
}

/* Los 12 bits altos de un double (signo y exponente); musl top12 de exp.c/pow.c. */
static inline uint32_t ce_top12(double x)
{
    return (uint32_t)(CE_ASUINT64(x) >> 52);
}

/* ======================================================================
 * ce_cbrt (musl src/math/cbrt.c)
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/s_cbrt.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 *
 * Optimized by Bruce D. Evans.
 */
/* cbrt(x)
 * Return cube root of x
 */
static const uint32_t
B1 = 715094163, /* B1 = (1023-1023/3-0.03306235651)*2**20 */
B2 = 696219795; /* B2 = (1023-1023/3-54/3-0.03306235651)*2**20 */

/* |1/cbrt(x) - p(x)| < 2**-23.5 (~[-7.93e-8, 7.929e-8]). */
static const double
P0 =  1.87595182427177009643,  /* 0x3ffe03e6, 0x0f61e692 */
P1 = -1.88497979543377169875,  /* 0xbffe28e0, 0x92f02420 */
P2 =  1.621429720105354466140, /* 0x3ff9f160, 0x4a49d6c2 */
P3 = -0.758397934778766047437, /* 0xbfe844cb, 0xbee751d9 */
P4 =  0.145996192886612446982; /* 0x3fc2b000, 0xd4e4edd7 */

double ce_cbrt(double x)
{
	union {double f; uint64_t i;} u = {x};
	double r,s,t,w;
	uint32_t hx = u.i>>32 & 0x7fffffff;

	if (hx >= 0x7ff00000)  /* cbrt(NaN,INF) is itself */
		return x+x;

	/*
	 * Rough cbrt to 5 bits:
	 *    cbrt(2**e*(1+m) ~= 2**(e/3)*(1+(e%3+m)/3)
	 * where e is integral and >= 0, m is real and in [0, 1), and "/" and
	 * "%" are integer division and modulus with rounding towards minus
	 * infinity.  The RHS is always >= the LHS and has a maximum relative
	 * error of about 1 in 16.  Adding a bias of -0.03306235651 to the
	 * (e%3+m)/3 term reduces the error to about 1 in 32. With the IEEE
	 * floating point representation, for finite positive normal values,
	 * ordinary integer divison of the value in bits magically gives
	 * almost exactly the RHS of the above provided we first subtract the
	 * exponent bias (1023 for doubles) and later add it back.  We do the
	 * subtraction virtually to keep e >= 0 so that ordinary integer
	 * division rounds towards minus infinity; this is also efficient.
	 */
	if (hx < 0x00100000) { /* zero or subnormal? */
		u.f = x*0x1p54;
		hx = u.i>>32 & 0x7fffffff;
		if (hx == 0)
			return x;  /* cbrt(0) is itself */
		hx = hx/3 + B2;
	} else
		hx = hx/3 + B1;
	u.i &= 1ULL<<63;
	u.i |= (uint64_t)hx << 32;
	t = u.f;

	/*
	 * New cbrt to 23 bits:
	 *    cbrt(x) = t*cbrt(x/t**3) ~= t*P(t**3/x)
	 * where P(r) is a polynomial of degree 4 that approximates 1/cbrt(r)
	 * to within 2**-23.5 when |r - 1| < 1/10.  The rough approximation
	 * has produced t such than |t/cbrt(x) - 1| ~< 1/32, and cubing this
	 * gives us bounds for r = t**3/x.
	 *
	 * Try to optimize for parallel evaluation as in __tanf.c.
	 */
	r = (t*t)*(t/x);
	t = t*((P0+r*(P1+r*P2))+((r*r)*r)*(P3+r*P4));

	/*
	 * Round t away from zero to 23 bits (sloppily except for ensuring that
	 * the result is larger in magnitude than cbrt(x) but not much more than
	 * 2 23-bit ulps larger).  With rounding towards zero, the error bound
	 * would be ~5/6 instead of ~4/6.  With a maximum error of 2 23-bit ulps
	 * in the rounded t, the infinite-precision error in the Newton
	 * approximation barely affects third digit in the final error
	 * 0.667; the error in the rounded t can be up to about 3 23-bit ulps
	 * before the final error is larger than 0.667 ulps.
	 */
	u.f = t;
	u.i = (u.i + 0x80000000) & 0xffffffffc0000000ULL;
	t = u.f;

	/* one step Newton iteration to 53 bits with error < 0.667 ulps */
	s = t*t;         /* t*t is exact */
	r = x/s;         /* error <= 0.5 ulps; |r| < |t| */
	w = t+t;         /* t+t is exact */
	r = (r-t)/(w+r); /* r-t is exact; w+r ~= 3*t */
	t = t+t*r;       /* error <= 0.5 + 0.5/3 + epsilon */
	return t;
}

/* ======================================================================
 * ce_atan (musl src/math/atan.c), auxiliar de ce_atan2
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/s_atan.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* atan(x)
 * Method
 *   1. Reduce x to positive by atan(x) = -atan(-x).
 *   2. According to the integer k=4t+0.25 chopped, t=x, the argument
 *      is further reduced to one of the following intervals and the
 *      arctangent of t is evaluated by the corresponding formula:
 *
 *      [0,7/16]      atan(x) = t-t^3*(a1+t^2*(a2+...(a10+t^2*a11)...)
 *      [7/16,11/16]  atan(x) = atan(1/2) + atan( (t-0.5)/(1+t/2) )
 *      [11/16.19/16] atan(x) = atan( 1 ) + atan( (t-1)/(1+t) )
 *      [19/16,39/16] atan(x) = atan(3/2) + atan( (t-1.5)/(1+1.5t) )
 *      [39/16,INF]   atan(x) = atan(INF) + atan( -1/t )
 *
 * Constants:
 * The hexadecimal values are the intended ones for the following
 * constants. The decimal values may be used, provided that the
 * compiler will convert from decimal to binary accurately enough
 * to produce the hexadecimal values shown.
 */
static const double atanhi[] = {
  4.63647609000806093515e-01, /* atan(0.5)hi 0x3FDDAC67, 0x0561BB4F */
  7.85398163397448278999e-01, /* atan(1.0)hi 0x3FE921FB, 0x54442D18 */
  9.82793723247329054082e-01, /* atan(1.5)hi 0x3FEF730B, 0xD281F69B */
  1.57079632679489655800e+00, /* atan(inf)hi 0x3FF921FB, 0x54442D18 */
};

static const double atanlo[] = {
  2.26987774529616870924e-17, /* atan(0.5)lo 0x3C7A2B7F, 0x222F65E2 */
  3.06161699786838301793e-17, /* atan(1.0)lo 0x3C81A626, 0x33145C07 */
  1.39033110312309984516e-17, /* atan(1.5)lo 0x3C700788, 0x7AF0CBBD */
  6.12323399573676603587e-17, /* atan(inf)lo 0x3C91A626, 0x33145C07 */
};

static const double aT[] = {
  3.33333333333329318027e-01, /* 0x3FD55555, 0x5555550D */
 -1.99999999998764832476e-01, /* 0xBFC99999, 0x9998EBC4 */
  1.42857142725034663711e-01, /* 0x3FC24924, 0x920083FF */
 -1.11111104054623557880e-01, /* 0xBFBC71C6, 0xFE231671 */
  9.09088713343650656196e-02, /* 0x3FB745CD, 0xC54C206E */
 -7.69187620504482999495e-02, /* 0xBFB3B0F2, 0xAF749A6D */
  6.66107313738753120669e-02, /* 0x3FB10D66, 0xA0D03D51 */
 -5.83357013379057348645e-02, /* 0xBFADDE2D, 0x52DEFD9A */
  4.97687799461593236017e-02, /* 0x3FA97B4B, 0x24760DEB */
 -3.65315727442169155270e-02, /* 0xBFA2B444, 0x2C6A6C2F */
  1.62858201153657823623e-02, /* 0x3F90AD3A, 0xE322DA11 */
};

static double ce_atan(double x)
{
	double w,s1,s2,z;
	uint32_t ix,sign;
	int id;

	CE_GET_HIGH_WORD(ix, x);
	sign = ix >> 31;
	ix &= 0x7fffffff;
	if (ix >= 0x44100000) {   /* if |x| >= 2^66 */
		if (isnan(x))
			return x;
		z = atanhi[3] + 0x1p-120f;
		return sign ? -z : z;
	}
	if (ix < 0x3fdc0000) {    /* |x| < 0.4375 */
		if (ix < 0x3e400000) {  /* |x| < 2^-27 */
			if (ix < 0x00100000)
				/* raise underflow for subnormal x */
				/* (musl: forzaba la evaluacion solo para senalizar excepciones FP; sin efecto en el valor) */
			return x;
		}
		id = -1;
	} else {
		x = fabs(x);
		if (ix < 0x3ff30000) {  /* |x| < 1.1875 */
			if (ix < 0x3fe60000) {  /*  7/16 <= |x| < 11/16 */
				id = 0;
				x = (2.0*x-1.0)/(2.0+x);
			} else {                /* 11/16 <= |x| < 19/16 */
				id = 1;
				x = (x-1.0)/(x+1.0);
			}
		} else {
			if (ix < 0x40038000) {  /* |x| < 2.4375 */
				id = 2;
				x = (x-1.5)/(1.0+1.5*x);
			} else {                /* 2.4375 <= |x| < 2^66 */
				id = 3;
				x = -1.0/x;
			}
		}
	}
	/* end of argument reduction */
	z = x*x;
	w = z*z;
	/* break sum from i=0 to 10 aT[i]z**(i+1) into odd and even poly */
	s1 = z*(aT[0]+w*(aT[2]+w*(aT[4]+w*(aT[6]+w*(aT[8]+w*aT[10])))));
	s2 = w*(aT[1]+w*(aT[3]+w*(aT[5]+w*(aT[7]+w*aT[9]))));
	if (id < 0)
		return x - x*(s1+s2);
	z = atanhi[id] - (x*(s1+s2) - atanlo[id] - x);
	return sign ? -z : z;
}

/* ======================================================================
 * ce_atan2 (musl src/math/atan2.c)
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/e_atan2.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 *
 */
/* atan2(y,x)
 * Method :
 *      1. Reduce y to positive by atan2(y,x)=-atan2(-y,x).
 *      2. Reduce x to positive by (if x and y are unexceptional):
 *              ARG (x+iy) = arctan(y/x)           ... if x > 0,
 *              ARG (x+iy) = pi - arctan[y/(-x)]   ... if x < 0,
 *
 * Special cases:
 *
 *      ATAN2((anything), NaN ) is NaN;
 *      ATAN2(NAN , (anything) ) is NaN;
 *      ATAN2(+-0, +(anything but NaN)) is +-0  ;
 *      ATAN2(+-0, -(anything but NaN)) is +-pi ;
 *      ATAN2(+-(anything but 0 and NaN), 0) is +-pi/2;
 *      ATAN2(+-(anything but INF and NaN), +INF) is +-0 ;
 *      ATAN2(+-(anything but INF and NaN), -INF) is +-pi;
 *      ATAN2(+-INF,+INF ) is +-pi/4 ;
 *      ATAN2(+-INF,-INF ) is +-3pi/4;
 *      ATAN2(+-INF, (anything but,0,NaN, and INF)) is +-pi/2;
 *
 * Constants:
 * The hexadecimal values are the intended ones for the following
 * constants. The decimal values may be used, provided that the
 * compiler will convert from decimal to binary accurately enough
 * to produce the hexadecimal values shown.
 */
static const double
pi     = 3.1415926535897931160E+00, /* 0x400921FB, 0x54442D18 */
pi_lo  = 1.2246467991473531772E-16; /* 0x3CA1A626, 0x33145C07 */

double ce_atan2(double y, double x)
{
	double z;
	uint32_t m,lx,ly,ix,iy;

	if (isnan(x) || isnan(y))
		return x+y;
	CE_EXTRACT_WORDS(ix, lx, x);
	CE_EXTRACT_WORDS(iy, ly, y);
	if (((ix-0x3ff00000) | lx) == 0)  /* x = 1.0 */
		return ce_atan(y);
	m = ((iy>>31)&1) | ((ix>>30)&2);  /* 2*sign(x)+sign(y) */
	ix = ix & 0x7fffffff;
	iy = iy & 0x7fffffff;

	/* when y = 0 */
	if ((iy|ly) == 0) {
		switch(m) {
		case 0:
		case 1: return y;   /* atan(+-0,+anything)=+-0 */
		case 2: return  pi; /* atan(+0,-anything) = pi */
		case 3: return -pi; /* atan(-0,-anything) =-pi */
		}
	}
	/* when x = 0 */
	if ((ix|lx) == 0)
		return m&1 ? -pi/2 : pi/2;
	/* when x is INF */
	if (ix == 0x7ff00000) {
		if (iy == 0x7ff00000) {
			switch(m) {
			case 0: return  pi/4;   /* atan(+INF,+INF) */
			case 1: return -pi/4;   /* atan(-INF,+INF) */
			case 2: return  3*pi/4; /* atan(+INF,-INF) */
			case 3: return -3*pi/4; /* atan(-INF,-INF) */
			}
		} else {
			switch(m) {
			case 0: return  0.0; /* atan(+...,+INF) */
			case 1: return -0.0; /* atan(-...,+INF) */
			case 2: return  pi;  /* atan(+...,-INF) */
			case 3: return -pi;  /* atan(-...,-INF) */
			}
		}
	}
	/* |y/x| > 0x1p64 */
	if (ix+(64<<20) < iy || iy == 0x7ff00000)
		return m&1 ? -pi/2 : pi/2;

	/* z = atan(|y/x|) without spurious underflow */
	if ((m&2) && iy+(64<<20) < ix)  /* |y/x| < 0x1p-64, x<0 */
		z = 0;
	else
		z = ce_atan(fabs(y/x));
	switch (m) {
	case 0: return z;              /* atan(+,+) */
	case 1: return -z;             /* atan(-,+) */
	case 2: return pi - (z-pi_lo); /* atan(+,-) */
	default: /* case 3 */
		return (z-pi_lo) - pi; /* atan(-,-) */
	}
}

/* ======================================================================
 * ce_ksin (musl src/math/__sin.c): seno en [-pi/4, pi/4]
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/k_sin.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* __sin( x, y, iy)
 * kernel sin function on ~[-pi/4, pi/4] (except on -0), pi/4 ~ 0.7854
 * Input x is assumed to be bounded by ~pi/4 in magnitude.
 * Input y is the tail of x.
 * Input iy indicates whether y is 0. (if iy=0, y assume to be 0).
 *
 * Algorithm
 *      1. Since sin(-x) = -sin(x), we need only to consider positive x.
 *      2. Callers must return sin(-0) = -0 without calling here since our
 *         odd polynomial is not evaluated in a way that preserves -0.
 *         Callers may do the optimization sin(x) ~ x for tiny x.
 *      3. sin(x) is approximated by a polynomial of degree 13 on
 *         [0,pi/4]
 *                               3            13
 *              sin(x) ~ x + S1*x + ... + S6*x
 *         where
 *
 *      |sin(x)         2     4     6     8     10     12  |     -58
 *      |----- - (1+S1*x +S2*x +S3*x +S4*x +S5*x  +S6*x   )| <= 2
 *      |  x                                               |
 *
 *      4. sin(x+y) = sin(x) + sin'(x')*y
 *                  ~ sin(x) + (1-x*x/2)*y
 *         For better accuracy, let
 *                   3      2      2      2      2
 *              r = x *(S2+x *(S3+x *(S4+x *(S5+x *S6))))
 *         then                   3    2
 *              sin(x) = x + (S1*x + (x *(r-y/2)+y))
 */
static const double
S1  = -1.66666666666666324348e-01, /* 0xBFC55555, 0x55555549 */
S2  =  8.33333333332248946124e-03, /* 0x3F811111, 0x1110F8A6 */
S3  = -1.98412698298579493134e-04, /* 0xBF2A01A0, 0x19C161D5 */
S4  =  2.75573137070700676789e-06, /* 0x3EC71DE3, 0x57B1FE7D */
S5  = -2.50507602534068634195e-08, /* 0xBE5AE5E6, 0x8A2B9CEB */
S6  =  1.58969099521155010221e-10; /* 0x3DE5D93A, 0x5ACFD57C */

static double ce_ksin(double x, double y, int iy)
{
	double z,r,v,w;

	z = x*x;
	w = z*z;
	r = S2 + z*(S3 + z*S4) + z*w*(S5 + z*S6);
	v = z*x;
	if (iy == 0)
		return x + v*(S1 + z*r);
	else
		return x - ((z*(0.5*y - v*r) - y) - v*S1);
}

/* ======================================================================
 * ce_kcos (musl src/math/__cos.c): coseno en [-pi/4, pi/4]
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/k_cos.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/*
 * __cos( x,  y )
 * kernel cos function on [-pi/4, pi/4], pi/4 ~ 0.785398164
 * Input x is assumed to be bounded by ~pi/4 in magnitude.
 * Input y is the tail of x.
 *
 * Algorithm
 *      1. Since cos(-x) = cos(x), we need only to consider positive x.
 *      2. if x < 2^-27 (hx<0x3e400000 0), return 1 with inexact if x!=0.
 *      3. cos(x) is approximated by a polynomial of degree 14 on
 *         [0,pi/4]
 *                                       4            14
 *              cos(x) ~ 1 - x*x/2 + C1*x + ... + C6*x
 *         where the remez error is
 *
 *      |              2     4     6     8     10    12     14 |     -58
 *      |cos(x)-(1-.5*x +C1*x +C2*x +C3*x +C4*x +C5*x  +C6*x  )| <= 2
 *      |                                                      |
 *
 *                     4     6     8     10    12     14
 *      4. let r = C1*x +C2*x +C3*x +C4*x +C5*x  +C6*x  , then
 *             cos(x) ~ 1 - x*x/2 + r
 *         since cos(x+y) ~ cos(x) - sin(x)*y
 *                        ~ cos(x) - x*y,
 *         a correction term is necessary in cos(x) and hence
 *              cos(x+y) = 1 - (x*x/2 - (r - x*y))
 *         For better accuracy, rearrange to
 *              cos(x+y) ~ w + (tmp + (r-x*y))
 *         where w = 1 - x*x/2 and tmp is a tiny correction term
 *         (1 - x*x/2 == w + tmp exactly in infinite precision).
 *         The exactness of w + tmp in infinite precision depends on w
 *         and tmp having the same precision as x.  If they have extra
 *         precision due to compiler bugs, then the extra precision is
 *         only good provided it is retained in all terms of the final
 *         expression for cos().  Retention happens in all cases tested
 *         under FreeBSD, so don't pessimize things by forcibly clipping
 *         any extra precision in w.
 */
static const double
C1  =  4.16666666666666019037e-02, /* 0x3FA55555, 0x5555554C */
C2  = -1.38888888888741095749e-03, /* 0xBF56C16C, 0x16C15177 */
C3  =  2.48015872894767294178e-05, /* 0x3EFA01A0, 0x19CB1590 */
C4  = -2.75573143513906633035e-07, /* 0xBE927E4F, 0x809C52AD */
C5  =  2.08757232129817482790e-09, /* 0x3E21EE9E, 0xBDB4B1C4 */
C6  = -1.13596475577881948265e-11; /* 0xBDA8FAE9, 0xBE8838D4 */

static double ce_kcos(double x, double y)
{
	double hz,z,r,w;

	z  = x*x;
	w  = z*z;
	r  = z*(C1+z*(C2+z*C3)) + w*w*(C4+z*(C5+z*C6));
	hz = 0.5*z;
	w  = 1.0-hz;
	return w + (((1.0-w)-hz) + (z*r-x*y));
}

/* ======================================================================
 * ce_scalbn (musl src/math/scalbn.c): x * 2^n exacto, auxiliar de la
 * reducción de argumento grande
 * ==================================================================== */
static double ce_scalbn(double x, int n)
{
	union {double f; uint64_t i;} u;
	double y = x;

	if (n > 1023) {
		y *= 0x1p1023;
		n -= 1023;
		if (n > 1023) {
			y *= 0x1p1023;
			n -= 1023;
			if (n > 1023)
				n = 1023;
		}
	} else if (n < -1022) {
		/* make sure final n < -53 to avoid double
		   rounding in the subnormal range */
		y *= 0x1p-1022 * 0x1p53;
		n += 1022 - 53;
		if (n < -1022) {
			y *= 0x1p-1022 * 0x1p53;
			n += 1022 - 53;
			if (n < -1022)
				n = -1022;
		}
	}
	u.i = (uint64_t)(0x3ff+n)<<52;
	x = y * u.f;
	return x;
}

/* ======================================================================
 * ce_rem_pio2_large (musl src/math/__rem_pio2_large.c): reducción de
 * argumento para |x| >= 2^20 * pi/2
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/k_rem_pio2.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/*
 * __rem_pio2_large(x,y,e0,nx,prec)
 * double x[],y[]; int e0,nx,prec;
 *
 * __rem_pio2_large return the last three digits of N with
 *              y = x - N*pi/2
 * so that |y| < pi/2.
 *
 * The method is to compute the integer (mod 8) and fraction parts of
 * (2/pi)*x without doing the full multiplication. In general we
 * skip the part of the product that are known to be a huge integer (
 * more accurately, = 0 mod 8 ). Thus the number of operations are
 * independent of the exponent of the input.
 *
 * (2/pi) is represented by an array of 24-bit integers in ipio2[].
 *
 * Input parameters:
 *      x[]     The input value (must be positive) is broken into nx
 *              pieces of 24-bit integers in double precision format.
 *              x[i] will be the i-th 24 bit of x. The scaled exponent
 *              of x[0] is given in input parameter e0 (i.e., x[0]*2^e0
 *              match x's up to 24 bits.
 *
 *              Example of breaking a double positive z into x[0]+x[1]+x[2]:
 *                      e0 = ilogb(z)-23
 *                      z  = scalbn(z,-e0)
 *              for i = 0,1,2
 *                      x[i] = floor(z)
 *                      z    = (z-x[i])*2**24
 *
 *
 *      y[]     ouput result in an array of double precision numbers.
 *              The dimension of y[] is:
 *                      24-bit  precision       1
 *                      53-bit  precision       2
 *                      64-bit  precision       2
 *                      113-bit precision       3
 *              The actual value is the sum of them. Thus for 113-bit
 *              precison, one may have to do something like:
 *
 *              long double t,w,r_head, r_tail;
 *              t = (long double)y[2] + (long double)y[1];
 *              w = (long double)y[0];
 *              r_head = t+w;
 *              r_tail = w - (r_head - t);
 *
 *      e0      The exponent of x[0]. Must be <= 16360 or you need to
 *              expand the ipio2 table.
 *
 *      nx      dimension of x[]
 *
 *      prec    an integer indicating the precision:
 *                      0       24  bits (single)
 *                      1       53  bits (double)
 *                      2       64  bits (extended)
 *                      3       113 bits (quad)
 *
 * External function:
 *      double scalbn(), floor();
 *
 *
 * Here is the description of some local variables:
 *
 *      jk      jk+1 is the initial number of terms of ipio2[] needed
 *              in the computation. The minimum and recommended value
 *              for jk is 3,4,4,6 for single, double, extended, and quad.
 *              jk+1 must be 2 larger than you might expect so that our
 *              recomputation test works. (Up to 24 bits in the integer
 *              part (the 24 bits of it that we compute) and 23 bits in
 *              the fraction part may be lost to cancelation before we
 *              recompute.)
 *
 *      jz      local integer variable indicating the number of
 *              terms of ipio2[] used.
 *
 *      jx      nx - 1
 *
 *      jv      index for pointing to the suitable ipio2[] for the
 *              computation. In general, we want
 *                      ( 2^e0*x[0] * ipio2[jv-1]*2^(-24jv) )/8
 *              is an integer. Thus
 *                      e0-3-24*jv >= 0 or (e0-3)/24 >= jv
 *              Hence jv = max(0,(e0-3)/24).
 *
 *      jp      jp+1 is the number of terms in PIo2[] needed, jp = jk.
 *
 *      q[]     double array with integral value, representing the
 *              24-bits chunk of the product of x and 2/pi.
 *
 *      q0      the corresponding exponent of q[0]. Note that the
 *              exponent for q[i] would be q0-24*i.
 *
 *      PIo2[]  double precision array, obtained by cutting pi/2
 *              into 24 bits chunks.
 *
 *      f[]     ipio2[] in floating point
 *
 *      iq[]    integer array by breaking up q[] in 24-bits chunk.
 *
 *      fq[]    final product of x*(2/pi) in fq[0],..,fq[jk]
 *
 *      ih      integer. If >0 it indicates q[] is >= 0.5, hence
 *              it also indicates the *sign* of the result.
 *
 */
/*
 * Constants:
 * The hexadecimal values are the intended ones for the following
 * constants. The decimal values may be used, provided that the
 * compiler will convert from decimal to binary accurately enough
 * to produce the hexadecimal values shown.
 */
static const int init_jk[] = {3,4,4,6}; /* initial value for jk */

/*
 * Table of constants for 2/pi, 396 Hex digits (476 decimal) of 2/pi
 *
 *              integer array, contains the (24*i)-th to (24*i+23)-th
 *              bit of 2/pi after binary point. The corresponding
 *              floating value is
 *
 *                      ipio2[i] * 2^(-24(i+1)).
 *
 * NB: This table must have at least (e0-3)/24 + jk terms.
 *     For quad precision (e0 <= 16360, jk = 6), this is 686.
 */
static const int32_t ipio2[] = {
0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62,
0x95993C, 0x439041, 0xFE5163, 0xABDEBB, 0xC561B7, 0x246E3A,
0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C, 0xFE1DEB, 0x1CB129,
0xA73EE8, 0x8235F5, 0x2EBB44, 0x84E99C, 0x7026B4, 0x5F7E41,
0x3991D6, 0x398353, 0x39F49C, 0x845F8B, 0xBDF928, 0x3B1FF8,
0x97FFDE, 0x05980F, 0xEF2F11, 0x8B5A0A, 0x6D1F6D, 0x367ECF,
0x27CB09, 0xB74F46, 0x3F669E, 0x5FEA2D, 0x7527BA, 0xC7EBE5,
0xF17B3D, 0x0739F7, 0x8A5292, 0xEA6BFB, 0x5FB11F, 0x8D5D08,
0x560330, 0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3,
0x91615E, 0xE61B08, 0x659985, 0x5F14A0, 0x68408D, 0xFFD880,
0x4D7327, 0x310606, 0x1556CA, 0x73A8C9, 0x60E27B, 0xC08C6B,

/* (musl: #if LDBL_MAX_EXP > 1024; aquí la tabla completa siempre) */
0x47C419, 0xC367CD, 0xDCE809, 0x2A8359, 0xC4768B, 0x961CA6,
0xDDAF44, 0xD15719, 0x053EA5, 0xFF0705, 0x3F7E33, 0xE832C2,
0xDE4F98, 0x327DBB, 0xC33D26, 0xEF6B1E, 0x5EF89F, 0x3A1F35,
0xCAF27F, 0x1D87F1, 0x21907C, 0x7C246A, 0xFA6ED5, 0x772D30,
0x433B15, 0xC614B5, 0x9D19C3, 0xC2C4AD, 0x414D2C, 0x5D000C,
0x467D86, 0x2D71E3, 0x9AC69B, 0x006233, 0x7CD2B4, 0x97A7B4,
0xD55537, 0xF63ED7, 0x1810A3, 0xFC764D, 0x2A9D64, 0xABD770,
0xF87C63, 0x57B07A, 0xE71517, 0x5649C0, 0xD9D63B, 0x3884A7,
0xCB2324, 0x778AD6, 0x23545A, 0xB91F00, 0x1B0AF1, 0xDFCE19,
0xFF319F, 0x6A1E66, 0x615799, 0x47FBAC, 0xD87F7E, 0xB76522,
0x89E832, 0x60BFE6, 0xCDC4EF, 0x09366C, 0xD43F5D, 0xD7DE16,
0xDE3B58, 0x929BDE, 0x2822D2, 0xE88628, 0x4D58E2, 0x32CAC6,
0x16E308, 0xCB7DE0, 0x50C017, 0xA71DF3, 0x5BE018, 0x34132E,
0x621283, 0x014883, 0x5B8EF5, 0x7FB0AD, 0xF2E91E, 0x434A48,
0xD36710, 0xD8DDAA, 0x425FAE, 0xCE616A, 0xA4280A, 0xB499D3,
0xF2A606, 0x7F775C, 0x83C2A3, 0x883C61, 0x78738A, 0x5A8CAF,
0xBDD76F, 0x63A62D, 0xCBBFF4, 0xEF818D, 0x67C126, 0x45CA55,
0x36D9CA, 0xD2A828, 0x8D61C2, 0x77C912, 0x142604, 0x9B4612,
0xC459C4, 0x44C5C8, 0x91B24D, 0xF31700, 0xAD43D4, 0xE54929,
0x10D5FD, 0xFCBE00, 0xCC941E, 0xEECE70, 0xF53E13, 0x80F1EC,
0xC3E7B3, 0x28F8C7, 0x940593, 0x3E71C1, 0xB3092E, 0xF3450B,
0x9C1288, 0x7B20AB, 0x9FB52E, 0xC29247, 0x2F327B, 0x6D550C,
0x90A772, 0x1FE76B, 0x96CB31, 0x4A1679, 0xE27941, 0x89DFF4,
0x9794E8, 0x84E6E2, 0x973199, 0x6BED88, 0x365F5F, 0x0EFDBB,
0xB49A48, 0x6CA467, 0x427271, 0x325D8D, 0xB8159F, 0x09E5BC,
0x25318D, 0x3974F7, 0x1C0530, 0x010C0D, 0x68084B, 0x58EE2C,
0x90AA47, 0x02E774, 0x24D6BD, 0xA67DF7, 0x72486E, 0xEF169F,
0xA6948E, 0xF691B4, 0x5153D1, 0xF20ACF, 0x339820, 0x7E4BF5,
0x6863B2, 0x5F3EDD, 0x035D40, 0x7F8985, 0x295255, 0xC06437,
0x10D86D, 0x324832, 0x754C5B, 0xD4714E, 0x6E5445, 0xC1090B,
0x69F52A, 0xD56614, 0x9D0727, 0x50045D, 0xDB3BB4, 0xC576EA,
0x17F987, 0x7D6B49, 0xBA271D, 0x296996, 0xACCCC6, 0x5414AD,
0x6AE290, 0x89D988, 0x50722C, 0xBEA404, 0x940777, 0x7030F3,
0x27FC00, 0xA871EA, 0x49C266, 0x3DE064, 0x83DD97, 0x973FA3,
0xFD9443, 0x8C860D, 0xDE4131, 0x9D3992, 0x8C70DD, 0xE7B717,
0x3BDF08, 0x2B3715, 0xA0805C, 0x93805A, 0x921110, 0xD8E80F,
0xAF806C, 0x4BFFDB, 0x0F9038, 0x761859, 0x15A562, 0xBBCB61,
0xB989C7, 0xBD4010, 0x04F2D2, 0x277549, 0xF6B6EB, 0xBB22DB,
0xAA140A, 0x2F2689, 0x768364, 0x333B09, 0x1A940E, 0xAA3A51,
0xC2A31D, 0xAEEDAF, 0x12265C, 0x4DC26D, 0x9C7A2D, 0x9756C0,
0x833F03, 0xF6F009, 0x8C402B, 0x99316D, 0x07B439, 0x15200C,
0x5BC3D8, 0xC492F5, 0x4BADC6, 0xA5CA4E, 0xCD37A7, 0x36A9E6,
0x9492AB, 0x6842DD, 0xDE6319, 0xEF8C76, 0x528B68, 0x37DBFC,
0xABA1AE, 0x3115DF, 0xA1AE00, 0xDAFB0C, 0x664D64, 0xB705ED,
0x306529, 0xBF5657, 0x3AFF47, 0xB9F96A, 0xF3BE75, 0xDF9328,
0x3080AB, 0xF68C66, 0x15CB04, 0x0622FA, 0x1DE4D9, 0xA4B33D,
0x8F1B57, 0x09CD36, 0xE9424E, 0xA4BE13, 0xB52333, 0x1AAAF0,
0xA8654F, 0xA5C1D2, 0x0F3F0B, 0xCD785B, 0x76F923, 0x048B7B,
0x721789, 0x53A6C6, 0xE26E6F, 0x00EBEF, 0x584A9B, 0xB7DAC4,
0xBA66AA, 0xCFCF76, 0x1D02D1, 0x2DF1B1, 0xC1998C, 0x77ADC3,
0xDA4886, 0xA05DF7, 0xF480C6, 0x2FF0AC, 0x9AECDD, 0xBC5C3F,
0x6DDED0, 0x1FC790, 0xB6DB2A, 0x3A25A3, 0x9AAF00, 0x9353AD,
0x0457B6, 0xB42D29, 0x7E804B, 0xA707DA, 0x0EAA76, 0xA1597B,
0x2A1216, 0x2DB7DC, 0xFDE5FA, 0xFEDB89, 0xFDBE89, 0x6C76E4,
0xFCA906, 0x70803E, 0x156E85, 0xFF87FD, 0x073E28, 0x336761,
0x86182A, 0xEABD4D, 0xAFE7B3, 0x6E6D8F, 0x396795, 0x5BBF31,
0x48D784, 0x16DF30, 0x432DC7, 0x356125, 0xCE70C9, 0xB8CB30,
0xFD6CBF, 0xA200A4, 0xE46C05, 0xA0DD5A, 0x476F21, 0xD21262,
0x845CB9, 0x496170, 0xE0566B, 0x015299, 0x375550, 0xB7D51E,
0xC4F133, 0x5F6E13, 0xE4305D, 0xA92E85, 0xC3B21D, 0x3632A1,
0xA4B708, 0xD4B1EA, 0x21F716, 0xE4698F, 0x77FF27, 0x80030C,
0x2D408D, 0xA0CD4F, 0x99A520, 0xD3A2B3, 0x0A5D2F, 0x42F9B4,
0xCBDA11, 0xD0BE7D, 0xC1DB9B, 0xBD17AB, 0x81A2CA, 0x5C6A08,
0x17552E, 0x550027, 0xF0147F, 0x8607E1, 0x640B14, 0x8D4196,
0xDEBE87, 0x2AFDDA, 0xB6256B, 0x34897B, 0xFEF305, 0x9EBFB9,
0x4F6A68, 0xA82A4A, 0x5AC44F, 0xBCF82D, 0x985AD7, 0x95C7F4,
0x8D4D0D, 0xA63A20, 0x5F57A4, 0xB13F14, 0x953880, 0x0120CC,
0x86DD71, 0xB6DEC9, 0xF560BF, 0x11654D, 0x6B0701, 0xACB08C,
0xD0C0B2, 0x485551, 0x0EFB1E, 0xC37295, 0x3B06A3, 0x3540C0,
0x7BDC06, 0xCC45E0, 0xFA294E, 0xC8CAD6, 0x41F3E8, 0xDE647C,
0xD8649B, 0x31BED9, 0xC397A4, 0xD45877, 0xC5E369, 0x13DAF0,
0x3C3ABA, 0x461846, 0x5F7555, 0xF5BDD2, 0xC6926E, 0x5D2EAC,
0xED440E, 0x423E1C, 0x87C461, 0xE9FD29, 0xF3D6E7, 0xCA7C22,
0x35916F, 0xC5E008, 0x8DD7FF, 0xE26A6E, 0xC6FDB0, 0xC10893,
0x745D7C, 0xB2AD6B, 0x9D6ECD, 0x7B723E, 0x6A11C6, 0xA9CFF7,
0xDF7329, 0xBAC9B5, 0x5100B7, 0x0DB2E2, 0x24BA74, 0x607DE5,
0x8AD874, 0x2C150D, 0x0C1881, 0x94667E, 0x162901, 0x767A9F,
0xBEFDFD, 0xEF4556, 0x367ED9, 0x13D9EC, 0xB9BA8B, 0xFC97C4,
0x27A831, 0xC36EF1, 0x36C594, 0x56A8D8, 0xB5A8B4, 0x0ECCCF,
0x2D8912, 0x34576F, 0x89562C, 0xE3CE99, 0xB920D6, 0xAA5E6B,
0x9C2A3E, 0xCC5F11, 0x4A0BFD, 0xFBF4E1, 0x6D3B8E, 0x2C86E2,
0x84D4E9, 0xA9B4FC, 0xD1EEEF, 0xC9352E, 0x61392F, 0x442138,
0xC8D91B, 0x0AFC81, 0x6A4AFB, 0xD81C2F, 0x84B453, 0x8C994E,
0xCC2254, 0xDC552A, 0xD6C6C0, 0x96190B, 0xB8701A, 0x649569,
0x605A26, 0xEE523F, 0x0F117F, 0x11B5F4, 0xF5CBFC, 0x2DBC34,
0xEEBC34, 0xCC5DE8, 0x605EDD, 0x9B8E67, 0xEF3392, 0xB817C9,
0x9B5861, 0xBC57E1, 0xC68351, 0x103ED8, 0x4871DD, 0xDD1C2D,
0xA118AF, 0x462C21, 0xD7F359, 0x987AD9, 0xC0549E, 0xFA864F,
0xFC0656, 0xAE79E5, 0x362289, 0x22AD38, 0xDC9367, 0xAAE855,
0x382682, 0x9BE7CA, 0xA40D51, 0xB13399, 0x0ED7A9, 0x480569,
0xF0B265, 0xA7887F, 0x974C88, 0x36D1F9, 0xB39221, 0x4A827B,
0x21CF98, 0xDC9F40, 0x5547DC, 0x3A74E1, 0x42EB67, 0xDF9DFE,
0x5FD45E, 0xA4677B, 0x7AACBA, 0xA2F655, 0x23882B, 0x55BA41,
0x086E59, 0x862A21, 0x834739, 0xE6E389, 0xD49EE5, 0x40FB49,
0xE956FF, 0xCA0F1C, 0x8A59C5, 0x2BFA94, 0xC5C1D3, 0xCFC50F,
0xAE5ADB, 0x86C547, 0x624385, 0x3B8621, 0x94792C, 0x876110,
0x7B4C2A, 0x1A2C80, 0x12BF43, 0x902688, 0x893C78, 0xE4C4A8,
0x7BDBE5, 0xC23AC4, 0xEAF426, 0x8A67F7, 0xBF920D, 0x2BA365,
0xB1933D, 0x0B7CBD, 0xDC51A4, 0x63DD27, 0xDDE169, 0x19949A,
0x9529A8, 0x28CE68, 0xB4ED09, 0x209F44, 0xCA984E, 0x638270,
0x237C7E, 0x32B90F, 0x8EF5A7, 0xE75614, 0x08F121, 0x2A9DB5,
0x4D7E6F, 0x5119A5, 0xABF9B5, 0xD6DF82, 0x61DD96, 0x023616,
0x9F3AC4, 0xA1A283, 0x6DED72, 0x7A8D39, 0xA9B882, 0x5C326B,
0x5B2746, 0xED3400, 0x7700D2, 0x55F4FC, 0x4D5901, 0x8071E0,
};

static const double PIo2[] = {
  1.57079625129699707031e+00, /* 0x3FF921FB, 0x40000000 */
  7.54978941586159635335e-08, /* 0x3E74442D, 0x00000000 */
  5.39030252995776476554e-15, /* 0x3CF84698, 0x80000000 */
  3.28200341580791294123e-22, /* 0x3B78CC51, 0x60000000 */
  1.27065575308067607349e-29, /* 0x39F01B83, 0x80000000 */
  1.22933308981111328932e-36, /* 0x387A2520, 0x40000000 */
  2.73370053816464559624e-44, /* 0x36E38222, 0x80000000 */
  2.16741683877804819444e-51, /* 0x3569F31D, 0x00000000 */
};

static int ce_rem_pio2_large(double *x, double *y, int e0, int nx, int prec)
{
	int32_t jz,jx,jv,jp,jk,carry,n,iq[20],i,j,k,m,q0,ih;
	double z,fw,f[20],fq[20],q[20];

	/* initialize jk*/
	jk = init_jk[prec];
	jp = jk;

	/* determine jx,jv,q0, note that 3>q0 */
	jx = nx-1;
	jv = (e0-3)/24;  if(jv<0) jv=0;
	q0 = e0-24*(jv+1);

	/* set up f[0] to f[jx+jk] where f[jx+jk] = ipio2[jv+jk] */
	j = jv-jx; m = jx+jk;
	for (i=0; i<=m; i++,j++)
		f[i] = j<0 ? 0.0 : (double)ipio2[j];

	/* compute q[0],q[1],...q[jk] */
	for (i=0; i<=jk; i++) {
		for (j=0,fw=0.0; j<=jx; j++)
			fw += x[j]*f[jx+i-j];
		q[i] = fw;
	}

	jz = jk;
recompute:
	/* distill q[] into iq[] reversingly */
	for (i=0,j=jz,z=q[jz]; j>0; i++,j--) {
		fw    = (double)(int32_t)(0x1p-24*z);
		iq[i] = (int32_t)(z - 0x1p24*fw);
		z     = q[j-1]+fw;
	}

	/* compute n */
	z  = ce_scalbn(z,q0);       /* actual value of z */
	z -= 8.0*floor(z*0.125); /* trim off integer >= 8 */
	n  = (int32_t)z;
	z -= (double)n;
	ih = 0;
	if (q0 > 0) {  /* need iq[jz-1] to determine n */
		i  = iq[jz-1]>>(24-q0); n += i;
		iq[jz-1] -= i<<(24-q0);
		ih = iq[jz-1]>>(23-q0);
	}
	else if (q0 == 0) ih = iq[jz-1]>>23;
	else if (z >= 0.5) ih = 2;

	if (ih > 0) {  /* q > 0.5 */
		n += 1; carry = 0;
		for (i=0; i<jz; i++) {  /* compute 1-q */
			j = iq[i];
			if (carry == 0) {
				if (j != 0) {
					carry = 1;
					iq[i] = 0x1000000 - j;
				}
			} else
				iq[i] = 0xffffff - j;
		}
		if (q0 > 0) {  /* rare case: chance is 1 in 12 */
			switch(q0) {
			case 1:
				iq[jz-1] &= 0x7fffff; break;
			case 2:
				iq[jz-1] &= 0x3fffff; break;
			}
		}
		if (ih == 2) {
			z = 1.0 - z;
			if (carry != 0)
				z -= ce_scalbn(1.0,q0);
		}
	}

	/* check if recomputation is needed */
	if (z == 0.0) {
		j = 0;
		for (i=jz-1; i>=jk; i--) j |= iq[i];
		if (j == 0) {  /* need recomputation */
			for (k=1; iq[jk-k]==0; k++) {}  /* k = no. of terms needed */

			for (i=jz+1; i<=jz+k; i++) {  /* add q[jz+1] to q[jz+k] */
				f[jx+i] = (double)ipio2[jv+i];
				for (j=0,fw=0.0; j<=jx; j++)
					fw += x[j]*f[jx+i-j];
				q[i] = fw;
			}
			jz += k;
			goto recompute;
		}
	}

	/* chop off zero terms */
	if (z == 0.0) {
		jz -= 1;
		q0 -= 24;
		while (iq[jz] == 0) {
			jz--;
			q0 -= 24;
		}
	} else { /* break z into 24-bit if necessary */
		z = ce_scalbn(z,-q0);
		if (z >= 0x1p24) {
			fw = (double)(int32_t)(0x1p-24*z);
			iq[jz] = (int32_t)(z - 0x1p24*fw);
			jz += 1;
			q0 += 24;
			iq[jz] = (int32_t)fw;
		} else
			iq[jz] = (int32_t)z;
	}

	/* convert integer "bit" chunk to floating-point value */
	fw = ce_scalbn(1.0,q0);
	for (i=jz; i>=0; i--) {
		q[i] = fw*(double)iq[i];
		fw *= 0x1p-24;
	}

	/* compute PIo2[0,...,jp]*q[jz,...,0] */
	for(i=jz; i>=0; i--) {
		for (fw=0.0,k=0; k<=jp && k<=jz-i; k++)
			fw += PIo2[k]*q[i+k];
		fq[jz-i] = fw;
	}

	/* compress fq[] into y[] */
	switch(prec) {
	case 0:
		fw = 0.0;
		for (i=jz; i>=0; i--)
			fw += fq[i];
		y[0] = ih==0 ? fw : -fw;
		break;
	case 1:
	case 2:
		fw = 0.0;
		for (i=jz; i>=0; i--)
			fw += fq[i];
		// TODO: drop excess precision here once double is used
		fw = (double)fw;
		y[0] = ih==0 ? fw : -fw;
		fw = fq[0]-fw;
		for (i=1; i<=jz; i++)
			fw += fq[i];
		y[1] = ih==0 ? fw : -fw;
		break;
	case 3:  /* painful */
		for (i=jz; i>0; i--) {
			fw      = fq[i-1]+fq[i];
			fq[i]  += fq[i-1]-fw;
			fq[i-1] = fw;
		}
		for (i=jz; i>1; i--) {
			fw      = fq[i-1]+fq[i];
			fq[i]  += fq[i-1]-fw;
			fq[i-1] = fw;
		}
		for (fw=0.0,i=jz; i>=2; i--)
			fw += fq[i];
		if (ih==0) {
			y[0] =  fq[0]; y[1] =  fq[1]; y[2] =  fw;
		} else {
			y[0] = -fq[0]; y[1] = -fq[1]; y[2] = -fw;
		}
	}
	return n&7;
}

/* ======================================================================
 * ce_rem_pio2 (musl src/math/__rem_pio2.c): x rem pi/2 en y[0] + y[1]
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/e_rem_pio2.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 *
 * Optimized by Bruce D. Evans.
 */
/* __rem_pio2(x,y)
 *
 * return the remainder of x rem pi/2 in y[0]+y[1]
 * use __rem_pio2_large() for large x
 */
#define EPS DBL_EPSILON /* FLT_EVAL_METHOD == 0 */

/*
 * invpio2:  53 bits of 2/pi
 * pio2_1:   first  33 bit of pi/2
 * pio2_1t:  pi/2 - pio2_1
 * pio2_2:   second 33 bit of pi/2
 * pio2_2t:  pi/2 - (pio2_1+pio2_2)
 * pio2_3:   third  33 bit of pi/2
 * pio2_3t:  pi/2 - (pio2_1+pio2_2+pio2_3)
 */
static const double
toint   = 1.5/EPS,
pio4    = 0x1.921fb54442d18p-1,
invpio2 = 6.36619772367581382433e-01, /* 0x3FE45F30, 0x6DC9C883 */
pio2_1  = 1.57079632673412561417e+00, /* 0x3FF921FB, 0x54400000 */
pio2_1t = 6.07710050650619224932e-11, /* 0x3DD0B461, 0x1A626331 */
pio2_2  = 6.07710050630396597660e-11, /* 0x3DD0B461, 0x1A600000 */
pio2_2t = 2.02226624879595063154e-21, /* 0x3BA3198A, 0x2E037073 */
pio2_3  = 2.02226624871116645580e-21, /* 0x3BA3198A, 0x2E000000 */
pio2_3t = 8.47842766036889956997e-32; /* 0x397B839A, 0x252049C1 */

/* caller must handle the case when reduction is not needed: |x| ~<= pi/4 */
static int ce_rem_pio2(double x, double *y)
{
	union {double f; uint64_t i;} u = {x};
	double z,w,t,r,fn;
	double tx[3],ty[2];
	uint32_t ix;
	int sign, n, ex, ey, i;

	sign = u.i>>63;
	ix = u.i>>32 & 0x7fffffff;
	if (ix <= 0x400f6a7a) {  /* |x| ~<= 5pi/4 */
		if ((ix & 0xfffff) == 0x921fb)  /* |x| ~= pi/2 or 2pi/2 */
			goto medium;  /* cancellation -- use medium case */
		if (ix <= 0x4002d97c) {  /* |x| ~<= 3pi/4 */
			if (!sign) {
				z = x - pio2_1;  /* one round good to 85 bits */
				y[0] = z - pio2_1t;
				y[1] = (z-y[0]) - pio2_1t;
				return 1;
			} else {
				z = x + pio2_1;
				y[0] = z + pio2_1t;
				y[1] = (z-y[0]) + pio2_1t;
				return -1;
			}
		} else {
			if (!sign) {
				z = x - 2*pio2_1;
				y[0] = z - 2*pio2_1t;
				y[1] = (z-y[0]) - 2*pio2_1t;
				return 2;
			} else {
				z = x + 2*pio2_1;
				y[0] = z + 2*pio2_1t;
				y[1] = (z-y[0]) + 2*pio2_1t;
				return -2;
			}
		}
	}
	if (ix <= 0x401c463b) {  /* |x| ~<= 9pi/4 */
		if (ix <= 0x4015fdbc) {  /* |x| ~<= 7pi/4 */
			if (ix == 0x4012d97c)  /* |x| ~= 3pi/2 */
				goto medium;
			if (!sign) {
				z = x - 3*pio2_1;
				y[0] = z - 3*pio2_1t;
				y[1] = (z-y[0]) - 3*pio2_1t;
				return 3;
			} else {
				z = x + 3*pio2_1;
				y[0] = z + 3*pio2_1t;
				y[1] = (z-y[0]) + 3*pio2_1t;
				return -3;
			}
		} else {
			if (ix == 0x401921fb)  /* |x| ~= 4pi/2 */
				goto medium;
			if (!sign) {
				z = x - 4*pio2_1;
				y[0] = z - 4*pio2_1t;
				y[1] = (z-y[0]) - 4*pio2_1t;
				return 4;
			} else {
				z = x + 4*pio2_1;
				y[0] = z + 4*pio2_1t;
				y[1] = (z-y[0]) + 4*pio2_1t;
				return -4;
			}
		}
	}
	if (ix < 0x413921fb) {  /* |x| ~< 2^20*(pi/2), medium size */
medium:
		/* rint(x/(pi/2)) */
		fn = (double)x*invpio2 + toint - toint;
		n = (int32_t)fn;
		r = x - fn*pio2_1;
		w = fn*pio2_1t;  /* 1st round, good to 85 bits */
		/* Matters with directed rounding. */
		if (CE_PREDICT_FALSE(r - w < -pio4)) {
			n--;
			fn--;
			r = x - fn*pio2_1;
			w = fn*pio2_1t;
		} else if (CE_PREDICT_FALSE(r - w > pio4)) {
			n++;
			fn++;
			r = x - fn*pio2_1;
			w = fn*pio2_1t;
		}
		y[0] = r - w;
		u.f = y[0];
		ey = u.i>>52 & 0x7ff;
		ex = ix>>20;
		if (ex - ey > 16) { /* 2nd round, good to 118 bits */
			t = r;
			w = fn*pio2_2;
			r = t - w;
			w = fn*pio2_2t - ((t-r)-w);
			y[0] = r - w;
			u.f = y[0];
			ey = u.i>>52 & 0x7ff;
			if (ex - ey > 49) {  /* 3rd round, good to 151 bits, covers all cases */
				t = r;
				w = fn*pio2_3;
				r = t - w;
				w = fn*pio2_3t - ((t-r)-w);
				y[0] = r - w;
			}
		}
		y[1] = (r - y[0]) - w;
		return n;
	}
	/*
	 * all other (large) arguments
	 */
	if (ix >= 0x7ff00000) {  /* x is inf or NaN */
		y[0] = y[1] = x - x;
		return 0;
	}
	/* set z = scalbn(|x|,-ilogb(x)+23) */
	u.f = x;
	u.i &= (uint64_t)-1>>12;
	u.i |= (uint64_t)(0x3ff + 23)<<52;
	z = u.f;
	for (i=0; i < 2; i++) {
		tx[i] = (double)(int32_t)z;
		z     = (z-tx[i])*0x1p24;
	}
	tx[i] = z;
	/* skip zero terms, first term is non-zero */
	while (tx[i] == 0.0)
		i--;
	n = ce_rem_pio2_large(tx,ty,(int)(ix>>20)-(0x3ff+23),i+1,1);
	if (sign) {
		y[0] = -ty[0];
		y[1] = -ty[1];
		return -n;
	}
	y[0] = ty[0];
	y[1] = ty[1];
	return n;
}

#undef EPS

/* ======================================================================
 * ce_sin (musl src/math/sin.c)
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/s_sin.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* sin(x)
 * Return sine function of x.
 *
 * kernel function:
 *      __sin            ... sine function on [-pi/4,pi/4]
 *      __cos            ... cose function on [-pi/4,pi/4]
 *      __rem_pio2       ... argument reduction routine
 *
 * Method.
 *      Let S,C and T denote the sin, cos and tan respectively on
 *      [-PI/4, +PI/4]. Reduce the argument x to y1+y2 = x-k*pi/2
 *      in [-pi/4 , +pi/4], and let n = k mod 4.
 *      We have
 *
 *          n        sin(x)      cos(x)        tan(x)
 *     ----------------------------------------------------------
 *          0          S           C             T
 *          1          C          -S            -1/T
 *          2         -S          -C             T
 *          3         -C           S            -1/T
 *     ----------------------------------------------------------
 *
 * Special cases:
 *      Let trig be any of sin, cos, or tan.
 *      trig(+-INF)  is NaN, with signals;
 *      trig(NaN)    is that NaN;
 *
 * Accuracy:
 *      TRIG(x) returns trig(x) nearly rounded
 */
double ce_sin(double x)
{
	double y[2];
	uint32_t ix;
	unsigned n;

	/* High word of x. */
	CE_GET_HIGH_WORD(ix, x);
	ix &= 0x7fffffff;

	/* |x| ~< pi/4 */
	if (ix <= 0x3fe921fb) {
		if (ix < 0x3e500000) {  /* |x| < 2**-26 */
			/* raise inexact if x != 0 and underflow if subnormal*/
			/* (musl: forzaba la evaluacion solo para senalizar excepciones FP; sin efecto en el valor) */
			return x;
		}
		return ce_ksin(x, 0.0, 0);
	}

	/* sin(Inf or NaN) is NaN */
	if (ix >= 0x7ff00000)
		return x - x;

	/* argument reduction needed */
	n = ce_rem_pio2(x, y);
	switch (n&3) {
	case 0: return  ce_ksin(y[0], y[1], 1);
	case 1: return  ce_kcos(y[0], y[1]);
	case 2: return -ce_ksin(y[0], y[1], 1);
	default:
		return -ce_kcos(y[0], y[1]);
	}
}

/* ======================================================================
 * ce_cos (musl src/math/cos.c)
 * ==================================================================== */
/* origin: FreeBSD /usr/src/lib/msun/src/s_cos.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* cos(x)
 * Return cosine function of x.
 *
 * kernel function:
 *      __sin           ... sine function on [-pi/4,pi/4]
 *      __cos           ... cosine function on [-pi/4,pi/4]
 *      __rem_pio2      ... argument reduction routine
 *
 * Method.
 *      Let S,C and T denote the sin, cos and tan respectively on
 *      [-PI/4, +PI/4]. Reduce the argument x to y1+y2 = x-k*pi/2
 *      in [-pi/4 , +pi/4], and let n = k mod 4.
 *      We have
 *
 *          n        sin(x)      cos(x)        tan(x)
 *     ----------------------------------------------------------
 *          0          S           C             T
 *          1          C          -S            -1/T
 *          2         -S          -C             T
 *          3         -C           S            -1/T
 *     ----------------------------------------------------------
 *
 * Special cases:
 *      Let trig be any of sin, cos, or tan.
 *      trig(+-INF)  is NaN, with signals;
 *      trig(NaN)    is that NaN;
 *
 * Accuracy:
 *      TRIG(x) returns trig(x) nearly rounded
 */
double ce_cos(double x)
{
	double y[2];
	uint32_t ix;
	unsigned n;

	CE_GET_HIGH_WORD(ix, x);
	ix &= 0x7fffffff;

	/* |x| ~< pi/4 */
	if (ix <= 0x3fe921fb) {
		if (ix < 0x3e46a09e) {  /* |x| < 2**-27 * sqrt(2) */
			/* raise inexact if x!=0 */
			/* (musl: forzaba la evaluacion solo para senalizar excepciones FP; sin efecto en el valor) */
			return 1.0;
		}
		return ce_kcos(x, 0);
	}

	/* cos(Inf or NaN) is NaN */
	if (ix >= 0x7ff00000)
		return x-x;

	/* argument reduction */
	n = ce_rem_pio2(x, y);
	switch (n&3) {
	case 0: return  ce_kcos(y[0], y[1]);
	case 1: return -ce_ksin(y[0], y[1], 1);
	case 2: return -ce_kcos(y[0], y[1]);
	default:
		return  ce_ksin(y[0], y[1], 1);
	}
}

/* ======================================================================
 * Tabla de exp/pow (musl src/math/exp_data.c + exp_data.h)
 * ==================================================================== */
/*
 * Shared data between exp, exp2 and pow.
 *
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */
#define EXP_TABLE_BITS 7
#define EXP_POLY_ORDER 5
#define EXP_USE_TOINT_NARROW 0
#define EXP2_POLY_ORDER 5
#define TOINT_INTRINSICS 0

struct ce_exp_data {
    double invln2N;
    double shift;
    double negln2hiN;
    double negln2loN;
    double poly[4]; /* Last four coefficients.  */
    double exp2_shift;
    double exp2_poly[EXP2_POLY_ORDER];
    uint64_t tab[2*(1 << EXP_TABLE_BITS)];
};

#define N (1 << EXP_TABLE_BITS)

static const struct ce_exp_data ce_exp_data = {
// N/ln2
.invln2N = 0x1.71547652b82fep0 * N,
// -ln2/N
.negln2hiN = -0x1.62e42fefa0000p-8,
.negln2loN = -0x1.cf79abc9e3b3ap-47,
// Used for rounding when !TOINT_INTRINSICS
#if EXP_USE_TOINT_NARROW
.shift = 0x1800000000.8p0,
#else
.shift = 0x1.8p52,
#endif
// exp polynomial coefficients.
.poly = {
// abs error: 1.555*2^-66
// ulp error: 0.509 (0.511 without fma)
// if |x| < ln2/256+eps
// abs error if |x| < ln2/256+0x1p-15: 1.09*2^-65
// abs error if |x| < ln2/128: 1.7145*2^-56
0x1.ffffffffffdbdp-2,
0x1.555555555543cp-3,
0x1.55555cf172b91p-5,
0x1.1111167a4d017p-7,
},
.exp2_shift = 0x1.8p52 / N,
// exp2 polynomial coefficients.
.exp2_poly = {
// abs error: 1.2195*2^-65
// ulp error: 0.507 (0.511 without fma)
// if |x| < 1/256
// abs error if |x| < 1/128: 1.9941*2^-56
0x1.62e42fefa39efp-1,
0x1.ebfbdff82c424p-3,
0x1.c6b08d70cf4b5p-5,
0x1.3b2abd24650ccp-7,
0x1.5d7e09b4e3a84p-10,
},
// 2^(k/N) ~= H[k]*(1 + T[k]) for int k in [0,N)
// tab[2*k] = CE_ASUINT64(T[k])
// tab[2*k+1] = CE_ASUINT64(H[k]) - (k << 52)/N
.tab = {
0x0, 0x3ff0000000000000,
0x3c9b3b4f1a88bf6e, 0x3feff63da9fb3335,
0xbc7160139cd8dc5d, 0x3fefec9a3e778061,
0xbc905e7a108766d1, 0x3fefe315e86e7f85,
0x3c8cd2523567f613, 0x3fefd9b0d3158574,
0xbc8bce8023f98efa, 0x3fefd06b29ddf6de,
0x3c60f74e61e6c861, 0x3fefc74518759bc8,
0x3c90a3e45b33d399, 0x3fefbe3ecac6f383,
0x3c979aa65d837b6d, 0x3fefb5586cf9890f,
0x3c8eb51a92fdeffc, 0x3fefac922b7247f7,
0x3c3ebe3d702f9cd1, 0x3fefa3ec32d3d1a2,
0xbc6a033489906e0b, 0x3fef9b66affed31b,
0xbc9556522a2fbd0e, 0x3fef9301d0125b51,
0xbc5080ef8c4eea55, 0x3fef8abdc06c31cc,
0xbc91c923b9d5f416, 0x3fef829aaea92de0,
0x3c80d3e3e95c55af, 0x3fef7a98c8a58e51,
0xbc801b15eaa59348, 0x3fef72b83c7d517b,
0xbc8f1ff055de323d, 0x3fef6af9388c8dea,
0x3c8b898c3f1353bf, 0x3fef635beb6fcb75,
0xbc96d99c7611eb26, 0x3fef5be084045cd4,
0x3c9aecf73e3a2f60, 0x3fef54873168b9aa,
0xbc8fe782cb86389d, 0x3fef4d5022fcd91d,
0x3c8a6f4144a6c38d, 0x3fef463b88628cd6,
0x3c807a05b0e4047d, 0x3fef3f49917ddc96,
0x3c968efde3a8a894, 0x3fef387a6e756238,
0x3c875e18f274487d, 0x3fef31ce4fb2a63f,
0x3c80472b981fe7f2, 0x3fef2b4565e27cdd,
0xbc96b87b3f71085e, 0x3fef24dfe1f56381,
0x3c82f7e16d09ab31, 0x3fef1e9df51fdee1,
0xbc3d219b1a6fbffa, 0x3fef187fd0dad990,
0x3c8b3782720c0ab4, 0x3fef1285a6e4030b,
0x3c6e149289cecb8f, 0x3fef0cafa93e2f56,
0x3c834d754db0abb6, 0x3fef06fe0a31b715,
0x3c864201e2ac744c, 0x3fef0170fc4cd831,
0x3c8fdd395dd3f84a, 0x3feefc08b26416ff,
0xbc86a3803b8e5b04, 0x3feef6c55f929ff1,
0xbc924aedcc4b5068, 0x3feef1a7373aa9cb,
0xbc9907f81b512d8e, 0x3feeecae6d05d866,
0xbc71d1e83e9436d2, 0x3feee7db34e59ff7,
0xbc991919b3ce1b15, 0x3feee32dc313a8e5,
0x3c859f48a72a4c6d, 0x3feedea64c123422,
0xbc9312607a28698a, 0x3feeda4504ac801c,
0xbc58a78f4817895b, 0x3feed60a21f72e2a,
0xbc7c2c9b67499a1b, 0x3feed1f5d950a897,
0x3c4363ed60c2ac11, 0x3feece086061892d,
0x3c9666093b0664ef, 0x3feeca41ed1d0057,
0x3c6ecce1daa10379, 0x3feec6a2b5c13cd0,
0x3c93ff8e3f0f1230, 0x3feec32af0d7d3de,
0x3c7690cebb7aafb0, 0x3feebfdad5362a27,
0x3c931dbdeb54e077, 0x3feebcb299fddd0d,
0xbc8f94340071a38e, 0x3feeb9b2769d2ca7,
0xbc87deccdc93a349, 0x3feeb6daa2cf6642,
0xbc78dec6bd0f385f, 0x3feeb42b569d4f82,
0xbc861246ec7b5cf6, 0x3feeb1a4ca5d920f,
0x3c93350518fdd78e, 0x3feeaf4736b527da,
0x3c7b98b72f8a9b05, 0x3feead12d497c7fd,
0x3c9063e1e21c5409, 0x3feeab07dd485429,
0x3c34c7855019c6ea, 0x3feea9268a5946b7,
0x3c9432e62b64c035, 0x3feea76f15ad2148,
0xbc8ce44a6199769f, 0x3feea5e1b976dc09,
0xbc8c33c53bef4da8, 0x3feea47eb03a5585,
0xbc845378892be9ae, 0x3feea34634ccc320,
0xbc93cedd78565858, 0x3feea23882552225,
0x3c5710aa807e1964, 0x3feea155d44ca973,
0xbc93b3efbf5e2228, 0x3feea09e667f3bcd,
0xbc6a12ad8734b982, 0x3feea012750bdabf,
0xbc6367efb86da9ee, 0x3fee9fb23c651a2f,
0xbc80dc3d54e08851, 0x3fee9f7df9519484,
0xbc781f647e5a3ecf, 0x3fee9f75e8ec5f74,
0xbc86ee4ac08b7db0, 0x3fee9f9a48a58174,
0xbc8619321e55e68a, 0x3fee9feb564267c9,
0x3c909ccb5e09d4d3, 0x3feea0694fde5d3f,
0xbc7b32dcb94da51d, 0x3feea11473eb0187,
0x3c94ecfd5467c06b, 0x3feea1ed0130c132,
0x3c65ebe1abd66c55, 0x3feea2f336cf4e62,
0xbc88a1c52fb3cf42, 0x3feea427543e1a12,
0xbc9369b6f13b3734, 0x3feea589994cce13,
0xbc805e843a19ff1e, 0x3feea71a4623c7ad,
0xbc94d450d872576e, 0x3feea8d99b4492ed,
0x3c90ad675b0e8a00, 0x3feeaac7d98a6699,
0x3c8db72fc1f0eab4, 0x3feeace5422aa0db,
0xbc65b6609cc5e7ff, 0x3feeaf3216b5448c,
0x3c7bf68359f35f44, 0x3feeb1ae99157736,
0xbc93091fa71e3d83, 0x3feeb45b0b91ffc6,
0xbc5da9b88b6c1e29, 0x3feeb737b0cdc5e5,
0xbc6c23f97c90b959, 0x3feeba44cbc8520f,
0xbc92434322f4f9aa, 0x3feebd829fde4e50,
0xbc85ca6cd7668e4b, 0x3feec0f170ca07ba,
0x3c71affc2b91ce27, 0x3feec49182a3f090,
0x3c6dd235e10a73bb, 0x3feec86319e32323,
0xbc87c50422622263, 0x3feecc667b5de565,
0x3c8b1c86e3e231d5, 0x3feed09bec4a2d33,
0xbc91bbd1d3bcbb15, 0x3feed503b23e255d,
0x3c90cc319cee31d2, 0x3feed99e1330b358,
0x3c8469846e735ab3, 0x3feede6b5579fdbf,
0xbc82dfcd978e9db4, 0x3feee36bbfd3f37a,
0x3c8c1a7792cb3387, 0x3feee89f995ad3ad,
0xbc907b8f4ad1d9fa, 0x3feeee07298db666,
0xbc55c3d956dcaeba, 0x3feef3a2b84f15fb,
0xbc90a40e3da6f640, 0x3feef9728de5593a,
0xbc68d6f438ad9334, 0x3feeff76f2fb5e47,
0xbc91eee26b588a35, 0x3fef05b030a1064a,
0x3c74ffd70a5fddcd, 0x3fef0c1e904bc1d2,
0xbc91bdfbfa9298ac, 0x3fef12c25bd71e09,
0x3c736eae30af0cb3, 0x3fef199bdd85529c,
0x3c8ee3325c9ffd94, 0x3fef20ab5fffd07a,
0x3c84e08fd10959ac, 0x3fef27f12e57d14b,
0x3c63cdaf384e1a67, 0x3fef2f6d9406e7b5,
0x3c676b2c6c921968, 0x3fef3720dcef9069,
0xbc808a1883ccb5d2, 0x3fef3f0b555dc3fa,
0xbc8fad5d3ffffa6f, 0x3fef472d4a07897c,
0xbc900dae3875a949, 0x3fef4f87080d89f2,
0x3c74a385a63d07a7, 0x3fef5818dcfba487,
0xbc82919e2040220f, 0x3fef60e316c98398,
0x3c8e5a50d5c192ac, 0x3fef69e603db3285,
0x3c843a59ac016b4b, 0x3fef7321f301b460,
0xbc82d52107b43e1f, 0x3fef7c97337b9b5f,
0xbc892ab93b470dc9, 0x3fef864614f5a129,
0x3c74b604603a88d3, 0x3fef902ee78b3ff6,
0x3c83c5ec519d7271, 0x3fef9a51fbc74c83,
0xbc8ff7128fd391f0, 0x3fefa4afa2a490da,
0xbc8dae98e223747d, 0x3fefaf482d8e67f1,
0x3c8ec3bc41aa2008, 0x3fefba1bee615a27,
0x3c842b94c3a9eb32, 0x3fefc52b376bba97,
0x3c8a64a931d185ee, 0x3fefd0765b6e4540,
0xbc8e37bae43be3ed, 0x3fefdbfdad9cbe14,
0x3c77893b4d91cd9d, 0x3fefe7c1819e90d8,
0x3c5305c14160cc89, 0x3feff3c22b8f71f1,
},
};
#undef N

/* ======================================================================
 * ce_exp (musl src/math/exp.c)
 * ==================================================================== */
/*
 * Double-precision e^x function.
 *
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */
#define N (1 << EXP_TABLE_BITS)
#define InvLn2N ce_exp_data.invln2N
#define NegLn2hiN ce_exp_data.negln2hiN
#define NegLn2loN ce_exp_data.negln2loN
#define Shift ce_exp_data.shift
#define T ce_exp_data.tab
#define C2 ce_exp_data.poly[5 - EXP_POLY_ORDER]
#define C3 ce_exp_data.poly[6 - EXP_POLY_ORDER]
#define C4 ce_exp_data.poly[7 - EXP_POLY_ORDER]
#define C5 ce_exp_data.poly[8 - EXP_POLY_ORDER]

/* Handle cases that may overflow or underflow when computing the result that
   is scale*(1+TMP) without intermediate rounding.  The bit representation of
   scale is in SBITS, however it has a computed exponent that may have
   overflown into the sign bit so that needs to be adjusted before using it as
   a double.  (int32_t)KI is the k used in the argument reduction and exponent
   adjustment of scale, positive k here means the result may overflow and
   negative k means the result may underflow.  */
static inline double ce_exp_specialcase(double tmp, uint64_t sbits, uint64_t ki)
{
	double scale, y;

	if ((ki & 0x80000000) == 0) {
		/* k > 0, the exponent of scale might have overflowed by <= 460.  */
		sbits -= 1009ull << 52;
		scale = CE_ASDOUBLE(sbits);
		y = 0x1p1009 * (scale + scale * tmp);
		return CE_EVAL_AS_DOUBLE(y);
	}
	/* k < 0, need special care in the subnormal range.  */
	sbits += 1022ull << 52;
	scale = CE_ASDOUBLE(sbits);
	y = scale + scale * tmp;
	if (y < 1.0) {
		/* Round y to the right precision before scaling it into the subnormal
		 range to avoid double rounding that can cause 0.5+E/2 ulp error where
		 E is the worst-case ulp error outside the subnormal range.  So this
		 is only useful if the goal is better than 1 ulp worst-case error.  */
		double hi, lo;
		lo = scale - y + scale * tmp;
		hi = 1.0 + y;
		lo = 1.0 - hi + y + lo;
		y = CE_EVAL_AS_DOUBLE(hi + lo) - 1.0;
		/* Avoid -0.0 with downward rounding.  */
		if (WANT_ROUNDING && y == 0.0)
			y = 0.0;
		/* The underflow exception needs to be signaled explicitly.  */
		/* (musl: forzaba la evaluacion solo para senalizar excepciones FP; sin efecto en el valor) */
	}
	y = 0x1p-1022 * y;
	return CE_EVAL_AS_DOUBLE(y);
}

double ce_exp(double x)
{
	uint32_t abstop;
	uint64_t ki, idx, top, sbits;
	double kd, z, r, r2, scale, tail, tmp;

	abstop = ce_top12(x) & 0x7ff;
	if (CE_PREDICT_FALSE(abstop - ce_top12(0x1p-54) >= ce_top12(512.0) - ce_top12(0x1p-54))) {
		if (abstop - ce_top12(0x1p-54) >= 0x80000000)
			/* Avoid spurious underflow for tiny x.  */
			/* Note: 0 is common input.  */
			return WANT_ROUNDING ? 1.0 + x : 1.0;
		if (abstop >= ce_top12(1024.0)) {
			if (CE_ASUINT64(x) == CE_ASUINT64(-INFINITY))
				return 0.0;
			if (abstop >= ce_top12(INFINITY))
				return 1.0 + x;
			if (CE_ASUINT64(x) >> 63)
				return ce_math_uflow(0);
			else
				return ce_math_oflow(0);
		}
		/* Large x is special cased below.  */
		abstop = 0;
	}

	/* exp(x) = 2^(k/N) * exp(r), with exp(r) in [2^(-1/2N),2^(1/2N)].  */
	/* x = ln2/N*k + r, with int k and r in [-ln2/2N, ln2/2N].  */
	z = InvLn2N * x;
#if TOINT_INTRINSICS
	kd = roundtoint(z);
	ki = converttoint(z);
#elif EXP_USE_TOINT_NARROW
	/* z - kd is in [-0.5-2^-16, 0.5] in all rounding modes.  */
	kd = CE_EVAL_AS_DOUBLE(z + Shift);
	ki = CE_ASUINT64(kd) >> 16;
	kd = (double)(int32_t)ki;
#else
	/* z - kd is in [-1, 1] in non-nearest rounding modes.  */
	kd = CE_EVAL_AS_DOUBLE(z + Shift);
	ki = CE_ASUINT64(kd);
	kd -= Shift;
#endif
	r = x + kd * NegLn2hiN + kd * NegLn2loN;
	/* 2^(k/N) ~= scale * (1 + tail).  */
	idx = 2 * (ki % N);
	top = ki << (52 - EXP_TABLE_BITS);
	tail = CE_ASDOUBLE(T[idx]);
	/* This is only a valid scale when -1023*N < k < 1024*N.  */
	sbits = T[idx + 1] + top;
	/* exp(x) = 2^(k/N) * exp(r) ~= scale + scale * (tail + exp(r) - 1).  */
	/* Evaluation is optimized assuming superscalar pipelined execution.  */
	r2 = r * r;
	/* Without fma the worst case error is 0.25/N ulp larger.  */
	/* Worst case error is less than 0.5+1.11/N+(abs poly error * 2^53) ulp.  */
	tmp = tail + r + r2 * (C2 + r * C3) + r2 * r2 * (C4 + r * C5);
	if (CE_PREDICT_FALSE(abstop == 0))
		return ce_exp_specialcase(tmp, sbits, ki);
	scale = CE_ASDOUBLE(sbits);
	/* Note: tmp == 0 or |tmp| > 2^-200 and scale > 2^-739, so there
	   is no spurious underflow here even without fma.  */
	return CE_EVAL_AS_DOUBLE(scale + scale * tmp);
}

#undef N
#undef InvLn2N
#undef NegLn2hiN
#undef NegLn2loN
#undef Shift
#undef T
#undef C2
#undef C3
#undef C4
#undef C5

/* ======================================================================
 * Tabla del logaritmo de pow (musl src/math/pow_data.c + pow_data.h)
 * ==================================================================== */
/*
 * Data for the log part of pow.
 *
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */
#define POW_LOG_TABLE_BITS 7
#define POW_LOG_POLY_ORDER 8

struct ce_pow_log_data {
    double ln2hi;
    double ln2lo;
    double poly[POW_LOG_POLY_ORDER - 1]; /* First coefficient is 1.  */
    /* Note: the pad field is unused, but allows slightly faster indexing.  */
    struct {
        double invc, pad, logc, logctail;
    } tab[1 << POW_LOG_TABLE_BITS];
};

#define N (1 << POW_LOG_TABLE_BITS)

static const struct ce_pow_log_data ce_pow_log_data = {
.ln2hi = 0x1.62e42fefa3800p-1,
.ln2lo = 0x1.ef35793c76730p-45,
.poly = {
// relative error: 0x1.11922ap-70
// in -0x1.6bp-8 0x1.6bp-8
// Coefficients are scaled to match the scaling during evaluation.
-0x1p-1,
0x1.555555555556p-2 * -2,
-0x1.0000000000006p-2 * -2,
0x1.999999959554ep-3 * 4,
-0x1.555555529a47ap-3 * 4,
0x1.2495b9b4845e9p-3 * -8,
-0x1.0002b8b263fc3p-3 * -8,
},
/* Algorithm:

	x = 2^k z
	log(x) = k ln2 + log(c) + log(z/c)
	log(z/c) = poly(z/c - 1)

where z is in [0x1.69555p-1; 0x1.69555p0] which is split into N subintervals
and z falls into the ith one, then table entries are computed as

	tab[i].invc = 1/c
	tab[i].logc = round(0x1p43*log(c))/0x1p43
	tab[i].logctail = (double)(log(c) - logc)

where c is chosen near the center of the subinterval such that 1/c has only a
few precision bits so z/c - 1 is exactly representible as double:

	1/c = center < 1 ? round(N/center)/N : round(2*N/center)/N/2

Note: |z/c - 1| < 1/N for the chosen c, |log(c) - logc - logctail| < 0x1p-97,
the last few bits of logc are rounded away so k*ln2hi + logc has no rounding
error and the interval for z is selected such that near x == 1, where log(x)
is tiny, large cancellation error is avoided in logc + poly(z/c - 1).  */
.tab = {
#define A(a, b, c) {a, 0, b, c},
A(0x1.6a00000000000p+0, -0x1.62c82f2b9c800p-2, 0x1.ab42428375680p-48)
A(0x1.6800000000000p+0, -0x1.5d1bdbf580800p-2, -0x1.ca508d8e0f720p-46)
A(0x1.6600000000000p+0, -0x1.5767717455800p-2, -0x1.362a4d5b6506dp-45)
A(0x1.6400000000000p+0, -0x1.51aad872df800p-2, -0x1.684e49eb067d5p-49)
A(0x1.6200000000000p+0, -0x1.4be5f95777800p-2, -0x1.41b6993293ee0p-47)
A(0x1.6000000000000p+0, -0x1.4618bc21c6000p-2, 0x1.3d82f484c84ccp-46)
A(0x1.5e00000000000p+0, -0x1.404308686a800p-2, 0x1.c42f3ed820b3ap-50)
A(0x1.5c00000000000p+0, -0x1.3a64c55694800p-2, 0x1.0b1c686519460p-45)
A(0x1.5a00000000000p+0, -0x1.347dd9a988000p-2, 0x1.5594dd4c58092p-45)
A(0x1.5800000000000p+0, -0x1.2e8e2bae12000p-2, 0x1.67b1e99b72bd8p-45)
A(0x1.5600000000000p+0, -0x1.2895a13de8800p-2, 0x1.5ca14b6cfb03fp-46)
A(0x1.5600000000000p+0, -0x1.2895a13de8800p-2, 0x1.5ca14b6cfb03fp-46)
A(0x1.5400000000000p+0, -0x1.22941fbcf7800p-2, -0x1.65a242853da76p-46)
A(0x1.5200000000000p+0, -0x1.1c898c1699800p-2, -0x1.fafbc68e75404p-46)
A(0x1.5000000000000p+0, -0x1.1675cababa800p-2, 0x1.f1fc63382a8f0p-46)
A(0x1.4e00000000000p+0, -0x1.1058bf9ae4800p-2, -0x1.6a8c4fd055a66p-45)
A(0x1.4c00000000000p+0, -0x1.0a324e2739000p-2, -0x1.c6bee7ef4030ep-47)
A(0x1.4a00000000000p+0, -0x1.0402594b4d000p-2, -0x1.036b89ef42d7fp-48)
A(0x1.4a00000000000p+0, -0x1.0402594b4d000p-2, -0x1.036b89ef42d7fp-48)
A(0x1.4800000000000p+0, -0x1.fb9186d5e4000p-3, 0x1.d572aab993c87p-47)
A(0x1.4600000000000p+0, -0x1.ef0adcbdc6000p-3, 0x1.b26b79c86af24p-45)
A(0x1.4400000000000p+0, -0x1.e27076e2af000p-3, -0x1.72f4f543fff10p-46)
A(0x1.4200000000000p+0, -0x1.d5c216b4fc000p-3, 0x1.1ba91bbca681bp-45)
A(0x1.4000000000000p+0, -0x1.c8ff7c79aa000p-3, 0x1.7794f689f8434p-45)
A(0x1.4000000000000p+0, -0x1.c8ff7c79aa000p-3, 0x1.7794f689f8434p-45)
A(0x1.3e00000000000p+0, -0x1.bc286742d9000p-3, 0x1.94eb0318bb78fp-46)
A(0x1.3c00000000000p+0, -0x1.af3c94e80c000p-3, 0x1.a4e633fcd9066p-52)
A(0x1.3a00000000000p+0, -0x1.a23bc1fe2b000p-3, -0x1.58c64dc46c1eap-45)
A(0x1.3a00000000000p+0, -0x1.a23bc1fe2b000p-3, -0x1.58c64dc46c1eap-45)
A(0x1.3800000000000p+0, -0x1.9525a9cf45000p-3, -0x1.ad1d904c1d4e3p-45)
A(0x1.3600000000000p+0, -0x1.87fa06520d000p-3, 0x1.bbdbf7fdbfa09p-45)
A(0x1.3400000000000p+0, -0x1.7ab890210e000p-3, 0x1.bdb9072534a58p-45)
A(0x1.3400000000000p+0, -0x1.7ab890210e000p-3, 0x1.bdb9072534a58p-45)
A(0x1.3200000000000p+0, -0x1.6d60fe719d000p-3, -0x1.0e46aa3b2e266p-46)
A(0x1.3000000000000p+0, -0x1.5ff3070a79000p-3, -0x1.e9e439f105039p-46)
A(0x1.3000000000000p+0, -0x1.5ff3070a79000p-3, -0x1.e9e439f105039p-46)
A(0x1.2e00000000000p+0, -0x1.526e5e3a1b000p-3, -0x1.0de8b90075b8fp-45)
A(0x1.2c00000000000p+0, -0x1.44d2b6ccb8000p-3, 0x1.70cc16135783cp-46)
A(0x1.2c00000000000p+0, -0x1.44d2b6ccb8000p-3, 0x1.70cc16135783cp-46)
A(0x1.2a00000000000p+0, -0x1.371fc201e9000p-3, 0x1.178864d27543ap-48)
A(0x1.2800000000000p+0, -0x1.29552f81ff000p-3, -0x1.48d301771c408p-45)
A(0x1.2600000000000p+0, -0x1.1b72ad52f6000p-3, -0x1.e80a41811a396p-45)
A(0x1.2600000000000p+0, -0x1.1b72ad52f6000p-3, -0x1.e80a41811a396p-45)
A(0x1.2400000000000p+0, -0x1.0d77e7cd09000p-3, 0x1.a699688e85bf4p-47)
A(0x1.2400000000000p+0, -0x1.0d77e7cd09000p-3, 0x1.a699688e85bf4p-47)
A(0x1.2200000000000p+0, -0x1.fec9131dbe000p-4, -0x1.575545ca333f2p-45)
A(0x1.2000000000000p+0, -0x1.e27076e2b0000p-4, 0x1.a342c2af0003cp-45)
A(0x1.2000000000000p+0, -0x1.e27076e2b0000p-4, 0x1.a342c2af0003cp-45)
A(0x1.1e00000000000p+0, -0x1.c5e548f5bc000p-4, -0x1.d0c57585fbe06p-46)
A(0x1.1c00000000000p+0, -0x1.a926d3a4ae000p-4, 0x1.53935e85baac8p-45)
A(0x1.1c00000000000p+0, -0x1.a926d3a4ae000p-4, 0x1.53935e85baac8p-45)
A(0x1.1a00000000000p+0, -0x1.8c345d631a000p-4, 0x1.37c294d2f5668p-46)
A(0x1.1a00000000000p+0, -0x1.8c345d631a000p-4, 0x1.37c294d2f5668p-46)
A(0x1.1800000000000p+0, -0x1.6f0d28ae56000p-4, -0x1.69737c93373dap-45)
A(0x1.1600000000000p+0, -0x1.51b073f062000p-4, 0x1.f025b61c65e57p-46)
A(0x1.1600000000000p+0, -0x1.51b073f062000p-4, 0x1.f025b61c65e57p-46)
A(0x1.1400000000000p+0, -0x1.341d7961be000p-4, 0x1.c5edaccf913dfp-45)
A(0x1.1400000000000p+0, -0x1.341d7961be000p-4, 0x1.c5edaccf913dfp-45)
A(0x1.1200000000000p+0, -0x1.16536eea38000p-4, 0x1.47c5e768fa309p-46)
A(0x1.1000000000000p+0, -0x1.f0a30c0118000p-5, 0x1.d599e83368e91p-45)
A(0x1.1000000000000p+0, -0x1.f0a30c0118000p-5, 0x1.d599e83368e91p-45)
A(0x1.0e00000000000p+0, -0x1.b42dd71198000p-5, 0x1.c827ae5d6704cp-46)
A(0x1.0e00000000000p+0, -0x1.b42dd71198000p-5, 0x1.c827ae5d6704cp-46)
A(0x1.0c00000000000p+0, -0x1.77458f632c000p-5, -0x1.cfc4634f2a1eep-45)
A(0x1.0c00000000000p+0, -0x1.77458f632c000p-5, -0x1.cfc4634f2a1eep-45)
A(0x1.0a00000000000p+0, -0x1.39e87b9fec000p-5, 0x1.502b7f526feaap-48)
A(0x1.0a00000000000p+0, -0x1.39e87b9fec000p-5, 0x1.502b7f526feaap-48)
A(0x1.0800000000000p+0, -0x1.f829b0e780000p-6, -0x1.980267c7e09e4p-45)
A(0x1.0800000000000p+0, -0x1.f829b0e780000p-6, -0x1.980267c7e09e4p-45)
A(0x1.0600000000000p+0, -0x1.7b91b07d58000p-6, -0x1.88d5493faa639p-45)
A(0x1.0400000000000p+0, -0x1.fc0a8b0fc0000p-7, -0x1.f1e7cf6d3a69cp-50)
A(0x1.0400000000000p+0, -0x1.fc0a8b0fc0000p-7, -0x1.f1e7cf6d3a69cp-50)
A(0x1.0200000000000p+0, -0x1.fe02a6b100000p-8, -0x1.9e23f0dda40e4p-46)
A(0x1.0200000000000p+0, -0x1.fe02a6b100000p-8, -0x1.9e23f0dda40e4p-46)
A(0x1.0000000000000p+0, 0x0.0000000000000p+0, 0x0.0000000000000p+0)
A(0x1.0000000000000p+0, 0x0.0000000000000p+0, 0x0.0000000000000p+0)
A(0x1.fc00000000000p-1, 0x1.0101575890000p-7, -0x1.0c76b999d2be8p-46)
A(0x1.f800000000000p-1, 0x1.0205658938000p-6, -0x1.3dc5b06e2f7d2p-45)
A(0x1.f400000000000p-1, 0x1.8492528c90000p-6, -0x1.aa0ba325a0c34p-45)
A(0x1.f000000000000p-1, 0x1.0415d89e74000p-5, 0x1.111c05cf1d753p-47)
A(0x1.ec00000000000p-1, 0x1.466aed42e0000p-5, -0x1.c167375bdfd28p-45)
A(0x1.e800000000000p-1, 0x1.894aa149fc000p-5, -0x1.97995d05a267dp-46)
A(0x1.e400000000000p-1, 0x1.ccb73cdddc000p-5, -0x1.a68f247d82807p-46)
A(0x1.e200000000000p-1, 0x1.eea31c006c000p-5, -0x1.e113e4fc93b7bp-47)
A(0x1.de00000000000p-1, 0x1.1973bd1466000p-4, -0x1.5325d560d9e9bp-45)
A(0x1.da00000000000p-1, 0x1.3bdf5a7d1e000p-4, 0x1.cc85ea5db4ed7p-45)
A(0x1.d600000000000p-1, 0x1.5e95a4d97a000p-4, -0x1.c69063c5d1d1ep-45)
A(0x1.d400000000000p-1, 0x1.700d30aeac000p-4, 0x1.c1e8da99ded32p-49)
A(0x1.d000000000000p-1, 0x1.9335e5d594000p-4, 0x1.3115c3abd47dap-45)
A(0x1.cc00000000000p-1, 0x1.b6ac88dad6000p-4, -0x1.390802bf768e5p-46)
A(0x1.ca00000000000p-1, 0x1.c885801bc4000p-4, 0x1.646d1c65aacd3p-45)
A(0x1.c600000000000p-1, 0x1.ec739830a2000p-4, -0x1.dc068afe645e0p-45)
A(0x1.c400000000000p-1, 0x1.fe89139dbe000p-4, -0x1.534d64fa10afdp-45)
A(0x1.c000000000000p-1, 0x1.1178e8227e000p-3, 0x1.1ef78ce2d07f2p-45)
A(0x1.be00000000000p-1, 0x1.1aa2b7e23f000p-3, 0x1.ca78e44389934p-45)
A(0x1.ba00000000000p-1, 0x1.2d1610c868000p-3, 0x1.39d6ccb81b4a1p-47)
A(0x1.b800000000000p-1, 0x1.365fcb0159000p-3, 0x1.62fa8234b7289p-51)
A(0x1.b400000000000p-1, 0x1.4913d8333b000p-3, 0x1.5837954fdb678p-45)
A(0x1.b200000000000p-1, 0x1.527e5e4a1b000p-3, 0x1.633e8e5697dc7p-45)
A(0x1.ae00000000000p-1, 0x1.6574ebe8c1000p-3, 0x1.9cf8b2c3c2e78p-46)
A(0x1.ac00000000000p-1, 0x1.6f0128b757000p-3, -0x1.5118de59c21e1p-45)
A(0x1.aa00000000000p-1, 0x1.7898d85445000p-3, -0x1.c661070914305p-46)
A(0x1.a600000000000p-1, 0x1.8beafeb390000p-3, -0x1.73d54aae92cd1p-47)
A(0x1.a400000000000p-1, 0x1.95a5adcf70000p-3, 0x1.7f22858a0ff6fp-47)
A(0x1.a000000000000p-1, 0x1.a93ed3c8ae000p-3, -0x1.8724350562169p-45)
A(0x1.9e00000000000p-1, 0x1.b31d8575bd000p-3, -0x1.c358d4eace1aap-47)
A(0x1.9c00000000000p-1, 0x1.bd087383be000p-3, -0x1.d4bc4595412b6p-45)
A(0x1.9a00000000000p-1, 0x1.c6ffbc6f01000p-3, -0x1.1ec72c5962bd2p-48)
A(0x1.9600000000000p-1, 0x1.db13db0d49000p-3, -0x1.aff2af715b035p-45)
A(0x1.9400000000000p-1, 0x1.e530effe71000p-3, 0x1.212276041f430p-51)
A(0x1.9200000000000p-1, 0x1.ef5ade4dd0000p-3, -0x1.a211565bb8e11p-51)
A(0x1.9000000000000p-1, 0x1.f991c6cb3b000p-3, 0x1.bcbecca0cdf30p-46)
A(0x1.8c00000000000p-1, 0x1.07138604d5800p-2, 0x1.89cdb16ed4e91p-48)
A(0x1.8a00000000000p-1, 0x1.0c42d67616000p-2, 0x1.7188b163ceae9p-45)
A(0x1.8800000000000p-1, 0x1.1178e8227e800p-2, -0x1.c210e63a5f01cp-45)
A(0x1.8600000000000p-1, 0x1.16b5ccbacf800p-2, 0x1.b9acdf7a51681p-45)
A(0x1.8400000000000p-1, 0x1.1bf99635a6800p-2, 0x1.ca6ed5147bdb7p-45)
A(0x1.8200000000000p-1, 0x1.214456d0eb800p-2, 0x1.a87deba46baeap-47)
A(0x1.7e00000000000p-1, 0x1.2bef07cdc9000p-2, 0x1.a9cfa4a5004f4p-45)
A(0x1.7c00000000000p-1, 0x1.314f1e1d36000p-2, -0x1.8e27ad3213cb8p-45)
A(0x1.7a00000000000p-1, 0x1.36b6776be1000p-2, 0x1.16ecdb0f177c8p-46)
A(0x1.7800000000000p-1, 0x1.3c25277333000p-2, 0x1.83b54b606bd5cp-46)
A(0x1.7600000000000p-1, 0x1.419b423d5e800p-2, 0x1.8e436ec90e09dp-47)
A(0x1.7400000000000p-1, 0x1.4718dc271c800p-2, -0x1.f27ce0967d675p-45)
A(0x1.7200000000000p-1, 0x1.4c9e09e173000p-2, -0x1.e20891b0ad8a4p-45)
A(0x1.7000000000000p-1, 0x1.522ae0738a000p-2, 0x1.ebe708164c759p-45)
A(0x1.6e00000000000p-1, 0x1.57bf753c8d000p-2, 0x1.fadedee5d40efp-46)
A(0x1.6c00000000000p-1, 0x1.5d5bddf596000p-2, -0x1.a0b2a08a465dcp-47)
},
};
#undef A
#undef N

/* ======================================================================
 * ce_pow (musl src/math/pow.c)
 * ==================================================================== */
/*
 * Double-precision x^y function.
 *
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */
/*
Worst-case error: 0.54 ULP (~= ulperr_exp + 1024*Ln2*relerr_log*2^53)
relerr_log: 1.3 * 2^-68 (Relative error of log, 1.5 * 2^-68 without fma)
ulperr_exp: 0.509 ULP (ULP error of exp, 0.511 ULP without fma)
*/

#define T ce_pow_log_data.tab
#define A ce_pow_log_data.poly
#define Ln2hi ce_pow_log_data.ln2hi
#define Ln2lo ce_pow_log_data.ln2lo
#define N (1 << POW_LOG_TABLE_BITS)
#define OFF 0x3fe6955500000000

/* Compute y+TAIL = log(x) where the rounded result is y and TAIL has about
   additional 15 bits precision.  IX is the bit representation of x, but
   normalized in the subnormal range using the sign bit for the exponent.  */
static inline double ce_pow_log_inline(uint64_t ix, double *tail)
{
	/* double for better performance on targets with FLT_EVAL_METHOD==2.  */
	double z, r, y, invc, logc, logctail, kd, hi, t1, t2, lo, lo1, lo2, p;
	uint64_t iz, tmp;
	int k, i;

	/* x = 2^k z; where z is in range [OFF,2*OFF) and exact.
	   The range is split into N subintervals.
	   The ith subinterval contains z and c is near its center.  */
	tmp = ix - OFF;
	i = (tmp >> (52 - POW_LOG_TABLE_BITS)) % N;
	k = (int64_t)tmp >> 52; /* arithmetic shift */
	iz = ix - (tmp & 0xfffULL << 52);
	z = CE_ASDOUBLE(iz);
	kd = (double)k;

	/* log(x) = k*Ln2 + log(c) + log1p(z/c-1).  */
	invc = T[i].invc;
	logc = T[i].logc;
	logctail = T[i].logctail;

	/* Note: 1/c is j/N or j/N/2 where j is an integer in [N,2N) and
     |z/c - 1| < 1/N, so r = z/c - 1 is exactly representible.  */
#if CE_LIBM_USE_FMA
	r = __builtin_fma(z, invc, -1.0);
#else
	/* Split z such that rhi, rlo and rhi*rhi are exact and |rlo| <= |r|.  */
	double zhi = CE_ASDOUBLE((iz + (1ULL << 31)) & (-1ULL << 32));
	double zlo = z - zhi;
	double rhi = zhi * invc - 1.0;
	double rlo = zlo * invc;
	r = rhi + rlo;
#endif

	/* k*Ln2 + log(c) + r.  */
	t1 = kd * Ln2hi + logc;
	t2 = t1 + r;
	lo1 = kd * Ln2lo + logctail;
	lo2 = t1 - t2 + r;

	/* Evaluation is optimized assuming superscalar pipelined execution.  */
	double ar, ar2, ar3, lo3, lo4;
	ar = A[0] * r; /* A[0] = -0.5.  */
	ar2 = r * ar;
	ar3 = r * ar2;
	/* k*Ln2 + log(c) + r + A[0]*r*r.  */
#if CE_LIBM_USE_FMA
	hi = t2 + ar2;
	lo3 = __builtin_fma(ar, r, -ar2);
	lo4 = t2 - hi + ar2;
#else
	double arhi = A[0] * rhi;
	double arhi2 = rhi * arhi;
	hi = t2 + arhi2;
	lo3 = rlo * (ar + arhi);
	lo4 = t2 - hi + arhi2;
#endif
	/* p = log1p(r) - r - A[0]*r*r.  */
	p = (ar3 * (A[1] + r * A[2] +
		    ar2 * (A[3] + r * A[4] + ar2 * (A[5] + r * A[6]))));
	lo = lo1 + lo2 + lo3 + lo4 + p;
	y = hi + lo;
	*tail = hi - y + lo;
	return y;
}

#undef N
#undef T
#define N (1 << EXP_TABLE_BITS)
#define InvLn2N ce_exp_data.invln2N
#define NegLn2hiN ce_exp_data.negln2hiN
#define NegLn2loN ce_exp_data.negln2loN
#define Shift ce_exp_data.shift
#define T ce_exp_data.tab
#define C2 ce_exp_data.poly[5 - EXP_POLY_ORDER]
#define C3 ce_exp_data.poly[6 - EXP_POLY_ORDER]
#define C4 ce_exp_data.poly[7 - EXP_POLY_ORDER]
#define C5 ce_exp_data.poly[8 - EXP_POLY_ORDER]
#define C6 ce_exp_data.poly[9 - EXP_POLY_ORDER]

/* Handle cases that may overflow or underflow when computing the result that
   is scale*(1+TMP) without intermediate rounding.  The bit representation of
   scale is in SBITS, however it has a computed exponent that may have
   overflown into the sign bit so that needs to be adjusted before using it as
   a double.  (int32_t)KI is the k used in the argument reduction and exponent
   adjustment of scale, positive k here means the result may overflow and
   negative k means the result may underflow.  */
static inline double ce_pow_specialcase(double tmp, uint64_t sbits, uint64_t ki)
{
	double scale, y;

	if ((ki & 0x80000000) == 0) {
		/* k > 0, the exponent of scale might have overflowed by <= 460.  */
		sbits -= 1009ull << 52;
		scale = CE_ASDOUBLE(sbits);
		y = 0x1p1009 * (scale + scale * tmp);
		return CE_EVAL_AS_DOUBLE(y);
	}
	/* k < 0, need special care in the subnormal range.  */
	sbits += 1022ull << 52;
	/* Note: sbits is signed scale.  */
	scale = CE_ASDOUBLE(sbits);
	y = scale + scale * tmp;
	if (fabs(y) < 1.0) {
		/* Round y to the right precision before scaling it into the subnormal
		   range to avoid double rounding that can cause 0.5+E/2 ulp error where
		   E is the worst-case ulp error outside the subnormal range.  So this
		   is only useful if the goal is better than 1 ulp worst-case error.  */
		double hi, lo, one = 1.0;
		if (y < 0.0)
			one = -1.0;
		lo = scale - y + scale * tmp;
		hi = one + y;
		lo = one - hi + y + lo;
		y = CE_EVAL_AS_DOUBLE(hi + lo) - one;
		/* Fix the sign of 0.  */
		if (y == 0.0)
			y = CE_ASDOUBLE(sbits & 0x8000000000000000);
		/* The underflow exception needs to be signaled explicitly.  */
		/* (musl: forzaba la evaluacion solo para senalizar excepciones FP; sin efecto en el valor) */
	}
	y = 0x1p-1022 * y;
	return CE_EVAL_AS_DOUBLE(y);
}

#define SIGN_BIAS (0x800 << EXP_TABLE_BITS)

/* Computes sign*exp(x+xtail) where |xtail| < 2^-8/N and |xtail| <= |x|.
   The sign_bias argument is SIGN_BIAS or 0 and sets the sign to -1 or 1.  */
static inline double ce_pow_exp_inline(double x, double xtail, uint32_t sign_bias)
{
	uint32_t abstop;
	uint64_t ki, idx, top, sbits;
	/* double for better performance on targets with FLT_EVAL_METHOD==2.  */
	double kd, z, r, r2, scale, tail, tmp;

	abstop = ce_top12(x) & 0x7ff;
	if (CE_PREDICT_FALSE(abstop - ce_top12(0x1p-54) >=
			  ce_top12(512.0) - ce_top12(0x1p-54))) {
		if (abstop - ce_top12(0x1p-54) >= 0x80000000) {
			/* Avoid spurious underflow for tiny x.  */
			/* Note: 0 is common input.  */
			double one = WANT_ROUNDING ? 1.0 + x : 1.0;
			return sign_bias ? -one : one;
		}
		if (abstop >= ce_top12(1024.0)) {
			/* Note: inf and nan are already handled.  */
			if (CE_ASUINT64(x) >> 63)
				return ce_math_uflow(sign_bias);
			else
				return ce_math_oflow(sign_bias);
		}
		/* Large x is special cased below.  */
		abstop = 0;
	}

	/* exp(x) = 2^(k/N) * exp(r), with exp(r) in [2^(-1/2N),2^(1/2N)].  */
	/* x = ln2/N*k + r, with int k and r in [-ln2/2N, ln2/2N].  */
	z = InvLn2N * x;
#if TOINT_INTRINSICS
	kd = roundtoint(z);
	ki = converttoint(z);
#elif EXP_USE_TOINT_NARROW
	/* z - kd is in [-0.5-2^-16, 0.5] in all rounding modes.  */
	kd = CE_EVAL_AS_DOUBLE(z + Shift);
	ki = CE_ASUINT64(kd) >> 16;
	kd = (double)(int32_t)ki;
#else
	/* z - kd is in [-1, 1] in non-nearest rounding modes.  */
	kd = CE_EVAL_AS_DOUBLE(z + Shift);
	ki = CE_ASUINT64(kd);
	kd -= Shift;
#endif
	r = x + kd * NegLn2hiN + kd * NegLn2loN;
	/* The code assumes 2^-200 < |xtail| < 2^-8/N.  */
	r += xtail;
	/* 2^(k/N) ~= scale * (1 + tail).  */
	idx = 2 * (ki % N);
	top = (ki + sign_bias) << (52 - EXP_TABLE_BITS);
	tail = CE_ASDOUBLE(T[idx]);
	/* This is only a valid scale when -1023*N < k < 1024*N.  */
	sbits = T[idx + 1] + top;
	/* exp(x) = 2^(k/N) * exp(r) ~= scale + scale * (tail + exp(r) - 1).  */
	/* Evaluation is optimized assuming superscalar pipelined execution.  */
	r2 = r * r;
	/* Without fma the worst case error is 0.25/N ulp larger.  */
	/* Worst case error is less than 0.5+1.11/N+(abs poly error * 2^53) ulp.  */
	tmp = tail + r + r2 * (C2 + r * C3) + r2 * r2 * (C4 + r * C5);
	if (CE_PREDICT_FALSE(abstop == 0))
		return ce_pow_specialcase(tmp, sbits, ki);
	scale = CE_ASDOUBLE(sbits);
	/* Note: tmp == 0 or |tmp| > 2^-200 and scale > 2^-739, so there
	   is no spurious underflow here even without fma.  */
	return CE_EVAL_AS_DOUBLE(scale + scale * tmp);
}

/* Returns 0 if not int, 1 if odd int, 2 if even int.  The argument is
   the bit representation of a non-zero finite floating-point value.  */
static inline int ce_pow_checkint(uint64_t iy)
{
	int e = iy >> 52 & 0x7ff;
	if (e < 0x3ff)
		return 0;
	if (e > 0x3ff + 52)
		return 2;
	if (iy & ((1ULL << (0x3ff + 52 - e)) - 1))
		return 0;
	if (iy & (1ULL << (0x3ff + 52 - e)))
		return 1;
	return 2;
}

/* Returns 1 if input is the bit representation of 0, infinity or nan.  */
static inline int ce_pow_zeroinfnan(uint64_t i)
{
	return 2 * i - 1 >= 2 * CE_ASUINT64(INFINITY) - 1;
}

double ce_pow(double x, double y)
{
	uint32_t sign_bias = 0;
	uint64_t ix, iy;
	uint32_t topx, topy;

	ix = CE_ASUINT64(x);
	iy = CE_ASUINT64(y);
	topx = ce_top12(x);
	topy = ce_top12(y);
	if (CE_PREDICT_FALSE(topx - 0x001 >= 0x7ff - 0x001 ||
			  (topy & 0x7ff) - 0x3be >= 0x43e - 0x3be)) {
		/* Note: if |y| > 1075 * ln2 * 2^53 ~= 0x1.749p62 then pow(x,y) = inf/0
		   and if |y| < 2^-54 / 1075 ~= 0x1.e7b6p-65 then pow(x,y) = +-1.  */
		/* Special cases: (x < 0x1p-126 or inf or nan) or
		   (|y| < 0x1p-65 or |y| >= 0x1p63 or nan).  */
		if (CE_PREDICT_FALSE(ce_pow_zeroinfnan(iy))) {
			if (2 * iy == 0)
				return CE_ISSIGNALING(x) ? x + y : 1.0;
			if (ix == CE_ASUINT64(1.0))
				return CE_ISSIGNALING(y) ? x + y : 1.0;
			if (2 * ix > 2 * CE_ASUINT64(INFINITY) ||
			    2 * iy > 2 * CE_ASUINT64(INFINITY))
				return x + y;
			if (2 * ix == 2 * CE_ASUINT64(1.0))
				return 1.0;
			if ((2 * ix < 2 * CE_ASUINT64(1.0)) == !(iy >> 63))
				return 0.0; /* |x|<1 && y==inf or |x|>1 && y==-inf.  */
			return y * y;
		}
		if (CE_PREDICT_FALSE(ce_pow_zeroinfnan(ix))) {
			double x2 = x * x;
			if (ix >> 63 && ce_pow_checkint(iy) == 1)
				x2 = -x2;
			/* Without the barrier some versions of clang hoist the 1/x2 and
			   thus division by zero exception can be signaled spuriously.  */
			return iy >> 63 ? ce_fp_barrier(1 / x2) : x2;
		}
		/* Here x and y are non-zero finite.  */
		if (ix >> 63) {
			/* Finite x < 0.  */
			int yint = ce_pow_checkint(iy);
			if (yint == 0)
				return ce_math_invalid(x);
			if (yint == 1)
				sign_bias = SIGN_BIAS;
			ix &= 0x7fffffffffffffff;
			topx &= 0x7ff;
		}
		if ((topy & 0x7ff) - 0x3be >= 0x43e - 0x3be) {
			/* Note: sign_bias == 0 here because y is not odd.  */
			if (ix == CE_ASUINT64(1.0))
				return 1.0;
			if ((topy & 0x7ff) < 0x3be) {
				/* |y| < 2^-65, x^y ~= 1 + y*log(x).  */
				if (WANT_ROUNDING)
					return ix > CE_ASUINT64(1.0) ? 1.0 + y :
								    1.0 - y;
				else
					return 1.0;
			}
			return (ix > CE_ASUINT64(1.0)) == (topy < 0x800) ?
				       ce_math_oflow(0) :
				       ce_math_uflow(0);
		}
		if (topx == 0) {
			/* Normalize subnormal x so exponent becomes negative.  */
			ix = CE_ASUINT64(x * 0x1p52);
			ix &= 0x7fffffffffffffff;
			ix -= 52ULL << 52;
		}
	}

	double lo;
	double hi = ce_pow_log_inline(ix, &lo);
	double ehi, elo;
#if CE_LIBM_USE_FMA
	ehi = y * hi;
	elo = y * lo + __builtin_fma(y, hi, -ehi);
#else
	double yhi = CE_ASDOUBLE(iy & -1ULL << 27);
	double ylo = y - yhi;
	double lhi = CE_ASDOUBLE(CE_ASUINT64(hi) & -1ULL << 27);
	double llo = hi - lhi + lo;
	ehi = yhi * lhi;
	elo = ylo * lhi + y * llo; /* |elo| < |ehi| * 2^-25.  */
#endif
	return ce_pow_exp_inline(ehi, elo, sign_bias);
}

#undef N
#undef T
#undef A
#undef Ln2hi
#undef Ln2lo
#undef OFF
#undef InvLn2N
#undef NegLn2hiN
#undef NegLn2loN
#undef Shift
#undef C2
#undef C3
#undef C4
#undef C5
#undef C6
#undef SIGN_BIAS
