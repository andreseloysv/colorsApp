// Migraciones v1-v4 sobre bases creadas con el DDL de cada versión (como
// SubjectDatabaseTests y GarmentDatabaseTests de iOS): cada versión sube a
// la última sin perder scans, unlocks, feedback ni ajustes.
package com.andreseloy.colorsapp.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.andreseloy.colorsapp.data.db.ColorsDatabase
import com.andreseloy.colorsapp.data.db.EngineVersions
import com.andreseloy.colorsapp.data.db.Migration1To2
import com.andreseloy.colorsapp.data.db.Migration2To3
import com.andreseloy.colorsapp.data.db.Migration3To4
import com.andreseloy.colorsapp.data.db.RoomFeedbackRepository
import com.andreseloy.colorsapp.data.db.RoomScanRepository
import com.andreseloy.colorsapp.data.db.RoomSettingsRepository
import com.andreseloy.colorsapp.data.db.RoomUnlockRepository
import com.andreseloy.colorsapp.subject.RegionMode
import com.andreseloy.colorsapp.subject.SubjectMode
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ColorsDatabaseMigrationTest {

    private lateinit var context: Context
    private val dbName = "colors-migration-test.sqlite"
    private var opened: ColorsDatabase? = null

    // Versiones de las filas semilla (las de la build v1/v3 de los tests de iOS).
    private val versions = EngineVersions(engineVersion = "0.1.0", dictVersion = "fd95ac692777")

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        context.deleteDatabase(dbName)
    }

    @After
    fun tearDown() {
        opened?.close()
        context.deleteDatabase(dbName)
    }

    /** Crea el fichero con el DDL de [version] y las filas semilla comunes. */
    private fun createLegacyDatabase(
        version: Int,
        personMask: String?,
        extra: (SQLiteDatabase) -> Unit = {},
    ) {
        val t = 1_788_000_000_000L
        val path = context.getDatabasePath(dbName)
        path.parentFile?.mkdirs()
        val db = SQLiteDatabase.openOrCreateDatabase(path, null)
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `scans` (`id` TEXT NOT NULL, `asset_local_id` TEXT, " +
                "`source` TEXT NOT NULL, `top1` INTEGER, `top2` INTEGER, `top3` INTEGER, " +
                "`scores` TEXT NOT NULL DEFAULT '[]', `palette_json` TEXT NOT NULL DEFAULT '[]', " +
                "`ambiguous` INTEGER NOT NULL DEFAULT 0, `engine_version` TEXT NOT NULL, " +
                "`dict_version` TEXT NOT NULL, `scanned_at` INTEGER NOT NULL, " +
                "`updated_at` INTEGER NOT NULL, `deleted_at` INTEGER, " +
                "`rev` INTEGER NOT NULL DEFAULT 1, `dirty` INTEGER NOT NULL DEFAULT 1, " +
                "PRIMARY KEY(`id`))",
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_scans_scanned_at` ON `scans` (`scanned_at`)")
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_scans_asset_local_id` ON `scans` (`asset_local_id`)")
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `unlocks` (`combo_id` INTEGER NOT NULL, " +
                "`first_seen_at` INTEGER NOT NULL, `source` TEXT NOT NULL, `asset_local_id` TEXT, " +
                "`scan_id` TEXT, `updated_at` INTEGER NOT NULL, `deleted_at` INTEGER, " +
                "`rev` INTEGER NOT NULL DEFAULT 1, `dirty` INTEGER NOT NULL DEFAULT 1, " +
                "PRIMARY KEY(`combo_id`))",
        )
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `feedback` (`id` TEXT NOT NULL, `scan_id` TEXT NOT NULL, " +
                "`verdict` TEXT NOT NULL, `created_at` INTEGER NOT NULL, " +
                "`updated_at` INTEGER NOT NULL, `deleted_at` INTEGER, " +
                "`rev` INTEGER NOT NULL DEFAULT 1, `dirty` INTEGER NOT NULL DEFAULT 1, " +
                "PRIMARY KEY(`id`))",
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_feedback_scan_id` ON `feedback` (`scan_id`)")
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `settings` (`key` TEXT NOT NULL, `value` TEXT NOT NULL, " +
                "`updated_at` INTEGER NOT NULL, `deleted_at` INTEGER, " +
                "`rev` INTEGER NOT NULL DEFAULT 1, `dirty` INTEGER NOT NULL DEFAULT 1, " +
                "PRIMARY KEY(`key`))",
        )
        if (version >= 2) {
            db.execSQL("ALTER TABLE scans ADD COLUMN subject_mode TEXT")
            db.execSQL("ALTER TABLE scans ADD COLUMN region_mode TEXT")
            db.execSQL("ALTER TABLE scans ADD COLUMN adaptive_skin INTEGER")
            db.execSQL("ALTER TABLE scans ADD COLUMN people_count INTEGER")
            db.execSQL("ALTER TABLE scans ADD COLUMN person_index INTEGER")
            db.execSQL("ALTER TABLE scans ADD COLUMN mask_steps TEXT")
            db.execSQL("ALTER TABLE scans ADD COLUMN mask_coverage REAL")
        }
        if (version >= 4) {
            db.execSQL("ALTER TABLE scans ADD COLUMN garments_json TEXT")
            db.execSQL("ALTER TABLE scans ADD COLUMN garment_regions INTEGER")
            db.execSQL("ALTER TABLE scans ADD COLUMN engine_policy_version INTEGER")
        }
        // Scan semilla (el de SubjectDatabaseTests).
        val subjectColumns = if (version >= 2) {
            ", 'largestPerson', 'clothing', 1, 2, 0, '[\"poseRegions\",\"skinExcluded\"]', 0.21"
        } else {
            ""
        }
        val subjectNames = if (version >= 2) {
            ", subject_mode, region_mode, adaptive_skin, people_count, person_index, mask_steps, mask_coverage"
        } else {
            ""
        }
        db.execSQL(
            "INSERT INTO scans (id, asset_local_id, source, top1, top2, top3, scores, " +
                "palette_json, ambiguous, engine_version, dict_version, scanned_at, updated_at, " +
                "deleted_at, rev, dirty$subjectNames) VALUES " +
                "('0190a000-0000-7000-8000-000000000001', 'asset-v1', 'camera', 12, 178, 3, " +
                "'[0.5,2,3]', '[{\"hex\":\"#c5a56e\",\"lab\":[70,3,33],\"rgb\":[197,165,110],\"weight\":1}]', " +
                "0, '0.1.0', 'fd95ac692777', $t, $t, NULL, 1, 1$subjectColumns)",
        )
        db.execSQL(
            "INSERT INTO unlocks (combo_id, first_seen_at, source, asset_local_id, scan_id, " +
                "updated_at, deleted_at, rev, dirty) VALUES " +
                "(12, $t, 'camera', 'asset-v1', '0190a000-0000-7000-8000-000000000001', $t, NULL, 1, 1), " +
                "(200, $t, 'library', NULL, NULL, $t, NULL, 1, 1)",
        )
        db.execSQL(
            "INSERT INTO feedback (id, scan_id, verdict, created_at, updated_at, deleted_at, rev, dirty) " +
                "VALUES ('0190a000-0000-7000-8000-0000000000f1', " +
                "'0190a000-0000-7000-8000-000000000001', 'yes', $t, $t, NULL, 1, 1)",
        )
        db.execSQL(
            "INSERT INTO settings (`key`, value, updated_at, deleted_at, rev, dirty) " +
                "VALUES ('initial_scan_done', 'true', $t, NULL, 1, 1)",
        )
        if (personMask != null) {
            db.execSQL(
                "INSERT INTO settings (`key`, value, updated_at, deleted_at, rev, dirty) " +
                    "VALUES ('person_mask', '$personMask', $t, NULL, 3, 0)",
            )
        }
        extra(db)
        db.version = version
        db.close()
    }

    /** Abre el fichero con Room (migra a v4) y fuerza la apertura. */
    private fun openMigrated(): ColorsDatabase {
        val db = Room.databaseBuilder(context, ColorsDatabase::class.java, dbName)
            .addMigrations(Migration1To2(), Migration2To3(), Migration3To4())
            .build()
        opened = db
        runBlocking { db.scanDao().liveCount() }
        return db
    }

    private fun assertSeedDataSurvives(db: ColorsDatabase) = runBlocking {
        assertEquals(setOf(12, 200), RoomUnlockRepository(db).unlockedIds())
        val record = RoomUnlockRepository(db).record(12)
        assertEquals("0190a000-0000-7000-8000-000000000001", record?.scanId)
        assertEquals(
            FeedbackVerdict.YES,
            RoomFeedbackRepository(db).latest("0190a000-0000-7000-8000-000000000001")?.verdict,
        )
        val scan = RoomScanRepository(db, versions)
            .fetch("0190a000-0000-7000-8000-000000000001")
            ?: throw AssertionError("scan semilla perdido")
        assertEquals(listOf(12, 178, 3), scan.topIds)
        assertEquals(listOf(0.5, 2.0, 3.0), scan.scoreValues)
        assertEquals("#c5a56e", scan.palette.first().hex)
        assertTrue(
            RoomSettingsRepository(db).bool(SettingsRepository.Key.INITIAL_SCAN_DONE),
        )
    }

    private fun assertUserVersion(db: ColorsDatabase, expected: Int) {
        db.openHelper.readableDatabase.query("PRAGMA user_version").use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(expected, cursor.getInt(0))
        }
    }

    private fun scanColumns(db: ColorsDatabase): Set<String> {
        val names = mutableSetOf<String>()
        db.openHelper.readableDatabase.query("PRAGMA table_info(scans)").use { cursor ->
            val nameIndex = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) names += cursor.getString(nameIndex)
        }
        return names
    }

    @Test
    fun v1SinPersonMaskSubeAV4SinPerderDatos() {
        createLegacyDatabase(version = 1, personMask = null)
        val db = openMigrated()
        assertUserVersion(db, 4)
        assertSeedDataSurvives(db)
        assertTrue(
            scanColumns(db).containsAll(
                setOf(
                    "subject_mode", "region_mode", "adaptive_skin", "people_count",
                    "person_index", "mask_steps", "mask_coverage", "garments_json",
                    "garment_regions", "engine_policy_version",
                ),
            ),
        )
        runBlocking {
            val scan = RoomScanRepository(db, versions)
                .fetch("0190a000-0000-7000-8000-000000000001")!!
            assertNull(scan.subjectMode)
            assertNull(scan.peopleCount)
            assertNull(scan.enginePolicyVersion)
            // Sin person_mask: ajustes por defecto nuevos.
            val settings = RoomSettingsRepository(db).subjectSettings()
            assertEquals(SubjectMode.LARGEST_PERSON, settings.mode)
            assertEquals(RegionMode.CLOTHING, settings.region)
            // El scan viejo pide re-análisis.
            assertEquals(
                listOf(scan.id),
                RoomScanRepository(db, versions).needingReanalysis().map { it.id },
            )
        }
    }

    @Test
    fun v1PersonMaskTrueAcabaEnLosDefectosNuevos() {
        createLegacyDatabase(version = 1, personMask = "true")
        val db = openMigrated()
        assertUserVersion(db, 4)
        assertSeedDataSurvives(db)
        runBlocking {
            val settings = RoomSettingsRepository(db)
            val subject = settings.subjectSettings()
            assertEquals(SubjectMode.LARGEST_PERSON, subject.mode)
            assertEquals(RegionMode.CLOTHING, subject.region)
            assertTrue(subject.adaptiveSkin)
            assertEquals(12.0, subject.unlockMaxScore, 0.0)
            assertNull(settings.get(SettingsRepository.Key.PERSON_MASK))
            assertNull(settings.get(SettingsRepository.Key.SUBJECT_MODE))
        }
        db.openHelper.readableDatabase.query(
            "SELECT deleted_at, rev, dirty FROM settings WHERE `key` = 'person_mask'",
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertTrue(!cursor.isNull(0))
            assertEquals(4, cursor.getInt(1))
            assertEquals(1, cursor.getInt(2))
        }
    }

    @Test
    fun v1PersonMaskFalseNoEscribeClavesNuevas() {
        createLegacyDatabase(version = 1, personMask = "false")
        val db = openMigrated()
        runBlocking {
            val settings = RoomSettingsRepository(db)
            assertNull(settings.get(SettingsRepository.Key.PERSON_MASK))
            assertNull(settings.get(SettingsRepository.Key.SUBJECT_MODE))
            assertEquals(SubjectMode.LARGEST_PERSON, settings.subjectSettings().mode)
        }
    }

    @Test
    fun v2ConLaConversionDeV2SeCorrigeEnV3() {
        // Base como la dejaría la build preliminar con v2 ya aplicada:
        // subject/region escritos por la conversión (updated_at == deleted_at
        // de person_mask).
        val t = 1_788_100_000_000L
        createLegacyDatabase(version = 2, personMask = null) { db ->
            db.execSQL(
                "INSERT INTO settings (`key`, value, updated_at, deleted_at, rev, dirty) VALUES " +
                    "('person_mask', 'true', $t, $t, 4, 1), " +
                    "('subject_mode', 'allPeople', $t, NULL, 1, 1), " +
                    "('region_mode', 'wholePerson', $t, NULL, 1, 1)",
            )
        }
        val db = openMigrated()
        assertUserVersion(db, 4)
        assertSeedDataSurvives(db)
        runBlocking {
            val subject = RoomSettingsRepository(db).subjectSettings()
            assertEquals(SubjectMode.LARGEST_PERSON, subject.mode)
            assertEquals(RegionMode.CLOTHING, subject.region)
            // Columnas de sujeto del scan v2 intactas.
            val scan = RoomScanRepository(db, versions)
                .fetch("0190a000-0000-7000-8000-000000000001")!!
            assertEquals("largestPerson", scan.subjectMode)
            assertEquals(2, scan.peopleCount)
        }
    }

    @Test
    fun v2ConEleccionDelUsuarioSeRespetaEnV3() {
        // El usuario eligió allPeople en Ajustes DESPUÉS de v2 (otro updated_at).
        val t = 1_788_100_000_000L
        createLegacyDatabase(version = 2, personMask = null) { db ->
            db.execSQL(
                "INSERT INTO settings (`key`, value, updated_at, deleted_at, rev, dirty) VALUES " +
                    "('person_mask', 'true', $t, $t, 4, 1), " +
                    "('subject_mode', 'allPeople', ${t + 60_000L}, NULL, 2, 1), " +
                    "('region_mode', 'wholePerson', ${t + 60_000L}, NULL, 2, 1)",
            )
        }
        val db = openMigrated()
        runBlocking {
            val subject = RoomSettingsRepository(db).subjectSettings()
            assertEquals(SubjectMode.ALL_PEOPLE, subject.mode)
            assertEquals(RegionMode.WHOLE_PERSON, subject.region)
        }
    }

    @Test
    fun v3SubeAV4ConColumnasNuevasNull() {
        createLegacyDatabase(version = 3, personMask = null)
        val db = openMigrated()
        assertUserVersion(db, 4)
        assertSeedDataSurvives(db)
        runBlocking {
            val scan = RoomScanRepository(db, versions)
                .fetch("0190a000-0000-7000-8000-000000000001")!!
            assertNull(scan.garmentsJson)
            assertNull(scan.garmentRegions)
            assertNull(scan.enginePolicyVersion)
            assertTrue(scan.garmentColors.isEmpty())
            assertEquals(
                listOf(
                    com.andreseloy.colorsapp.subject.MaskStep.POSE_REGIONS,
                    com.andreseloy.colorsapp.subject.MaskStep.SKIN_EXCLUDED,
                ),
                scan.maskStepValues,
            )
            assertEquals(0.21, scan.maskCoverage!!, 1e-12)
        }
    }

    @Test
    fun reabrirNoVuelveAMigrarNiBorra() {
        createLegacyDatabase(version = 1, personMask = "true")
        openMigrated().close()
        val again = openMigrated()
        assertUserVersion(again, 4)
        assertSeedDataSurvives(again)
    }

    @Test
    fun v4RoundTripConPrendasYSujeto() {
        createLegacyDatabase(version = 4, personMask = null)
        val db = openMigrated()
        assertNotNull(db)
        runBlocking {
            val scans = RoomScanRepository(db, versions)
            val record = ScanRecord(
                id = UuidV7.string(), assetId = "asset-2", source = ScanSource.CAMERA,
                top1 = 27, top2 = 337, top3 = null, scoresJson = "[21.55,22.1]",
                paletteJson = "[{\"hex\":\"#ddc0c8\",\"lab\":[79.5,8.1,0.4],\"rgb\":[221,192,200],\"weight\":0.6}]",
                engineVersion = "0.1.0", dictVersion = "fd95ac692777",
                scannedAtMs = 1_700_000_000_000L, updatedAtMs = 1_700_000_000_000L,
                subjectMode = "selectedPerson", regionMode = "clothing", adaptiveSkin = true,
                peopleCount = 3, personIndex = 2,
                maskStepsJson = "[\"poseRegions\",\"skinGuard\"]", maskCoverage = 0.125,
                garmentsJson = JsonCoding.encodeGarments(
                    listOf(
                        GarmentEntry(
                            "#ddc0c8", listOf(221, 192, 200), listOf(79.5, 8.1, 0.4),
                            weight = 0.6, region = 2, regionShare = 0.45, mergedClusters = 4,
                        ),
                    ),
                ),
                garmentRegions = 2, enginePolicyVersion = AnalysisPolicy.CURRENT,
            )
            scans.insert(record)
            val back = scans.fetch(record.id)!!
            assertEquals(record, back)
            assertEquals(2, back.garmentRegions)
            assertEquals(listOf("Parte de abajo"), back.garmentColors.map { it.region }.map {
                if (it == 2) "Parte de abajo" else "otra"
            })
            // Recién analizado con las versiones inyectadas: no pide re-análisis.
            assertTrue(scans.needingReanalysis().none { it.id == record.id })
        }
    }
}
