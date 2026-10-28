// Base de datos Room de la app: espejo de ios/ColorsApp/DB/AppDatabase.swift.
// Mismo fichero lógico (colors.sqlite), mismas tablas y las migraciones
// v1 -> v2 -> v3 -> v4 con la misma semántica que las de GRDB. Nunca
// fallbackToDestructiveMigration (en iOS eraseDatabaseOnSchemaChange es
// false también en Debug: hay desbloqueos del usuario). Las migraciones
// usan SQL literal y no dependen de los tipos de Records.kt, que evolucionan.
package com.andreseloy.colorsapp.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [ScanEntity::class, UnlockEntity::class, FeedbackEntity::class, SettingEntity::class],
    version = 4,
    exportSchema = true,
)
abstract class ColorsDatabase : RoomDatabase() {
    abstract fun scanDao(): ScanDao
    abstract fun unlockDao(): UnlockDao
    abstract fun feedbackDao(): FeedbackDao
    abstract fun settingDao(): SettingDao

    companion object {
        const val FILE_NAME = "colors.sqlite"
        const val VERSION = 4

        /** Abre (o crea) la base de datos en el almacenamiento interno de la app. */
        fun open(context: Context, name: String = FILE_NAME): ColorsDatabase =
            Room.databaseBuilder(context.applicationContext, ColorsDatabase::class.java, name)
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4)
                .build()

        /** Base de datos en memoria (tests y previews), como `AppDatabase.inMemory()`. */
        fun inMemory(context: Context): ColorsDatabase =
            Room.inMemoryDatabaseBuilder(context.applicationContext, ColorsDatabase::class.java)
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4)
                .build()

        /** Todas las migraciones, en orden (para builders de test con fichero). */
        val ALL_MIGRATIONS: Array<Migration> =
            arrayOf(Migration1To2(), Migration2To3(), Migration3To4())

        val MIGRATION_1_2: Migration = Migration1To2()
        val MIGRATION_2_3: Migration = Migration2To3()
        val MIGRATION_3_4: Migration = Migration3To4()
    }
}

/**
 * v2: recorte de sujeto por scan y conversión del ajuste `person_mask`,
 * igual que `AppDatabase.migrateV2` en iOS.
 *
 * - `scans` gana subject_mode, region_mode, adaptive_skin, people_count,
 *   person_index, mask_steps y mask_coverage (NULL en los scans de v1).
 * - `person_mask` = "true"/"1" pasa a subject_mode = allPeople +
 *   region_mode = wholePerson (v3 lo corrige después); "false" o ausente no
 *   escribe nada. La clave heredada se marca borrada (rev + 1, dirty).
 *
 * El INSERT ... ON CONFLICT DO UPDATE de iOS exige SQLite 3.24 y API 26
 * trae 3.18, así que el upsert se hace con UPDATE + INSERT si no hubo fila.
 */
class Migration1To2(private val nowMs: () -> Long = System::currentTimeMillis) : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE scans ADD COLUMN subject_mode TEXT")
        db.execSQL("ALTER TABLE scans ADD COLUMN region_mode TEXT")
        db.execSQL("ALTER TABLE scans ADD COLUMN adaptive_skin INTEGER")
        db.execSQL("ALTER TABLE scans ADD COLUMN people_count INTEGER")
        db.execSQL("ALTER TABLE scans ADD COLUMN person_index INTEGER")
        db.execSQL("ALTER TABLE scans ADD COLUMN mask_steps TEXT")
        db.execSQL("ALTER TABLE scans ADD COLUMN mask_coverage REAL")

        val legacy = db.query(
            "SELECT value FROM settings WHERE `key` = 'person_mask' AND deleted_at IS NULL",
        ).use { cursor -> if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null }
            ?: return
        val now = nowMs()
        if (legacy == "true" || legacy == "1") {
            for ((key, value) in listOf("subject_mode" to "allPeople", "region_mode" to "wholePerson")) {
                db.execSQL(
                    "UPDATE settings SET value = ?, updated_at = ?, deleted_at = NULL, " +
                        "rev = rev + 1, dirty = 1 WHERE `key` = ?",
                    arrayOf<Any>(value, now, key),
                )
                val changed = db.query("SELECT changes()").use { cursor ->
                    if (cursor.moveToFirst()) cursor.getInt(0) else 0
                }
                if (changed == 0) {
                    db.execSQL(
                        "INSERT INTO settings (`key`, value, updated_at, deleted_at, rev, dirty) " +
                            "VALUES (?, ?, ?, NULL, 1, 1)",
                        arrayOf<Any>(key, value, now),
                    )
                }
            }
        }
        db.execSQL(
            "UPDATE settings SET deleted_at = ?, updated_at = ?, rev = rev + 1, dirty = 1 " +
                "WHERE `key` = 'person_mask'",
            arrayOf<Any>(now, now),
        )
    }
}

/**
 * v3: `person_mask` = true acaba en los valores por defecto nuevos, igual
 * que `AppDatabase.migrateV3`: borra (suave) las filas subject_mode =
 * allPeople / region_mode = wholePerson que escribió la conversión de v2,
 * reconocibles porque su updated_at es exactamente el deleted_at de
 * `person_mask`. Si el usuario eligió después esos modos, updated_at es
 * otro y se respetan. adaptive_skin no se toca.
 */
class Migration2To3(private val nowMs: () -> Long = System::currentTimeMillis) : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        val now = nowMs()
        db.execSQL(
            """
            UPDATE settings
            SET deleted_at = ?, updated_at = ?, rev = rev + 1, dirty = 1
            WHERE deleted_at IS NULL
              AND ((`key` = 'subject_mode' AND value = 'allPeople')
                OR (`key` = 'region_mode' AND value = 'wholePerson'))
              AND updated_at = (SELECT pm.deleted_at FROM settings pm
                                WHERE pm.`key` = 'person_mask' AND pm.deleted_at IS NOT NULL
                                  AND pm.value IN ('true', '1'))
            """.trimIndent(),
            arrayOf<Any>(now, now),
        )
    }
}

/**
 * v4 (aditiva): paleta por prenda y versión de la política de análisis,
 * igual que `AppDatabase.migrateV4`. Las tres columnas quedan NULL en los
 * scans anteriores; nada se reescribe.
 */
class Migration3To4 : Migration(3, 4) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE scans ADD COLUMN garments_json TEXT")
        db.execSQL("ALTER TABLE scans ADD COLUMN garment_regions INTEGER")
        db.execSQL("ALTER TABLE scans ADD COLUMN engine_policy_version INTEGER")
    }
}
