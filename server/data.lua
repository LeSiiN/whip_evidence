-- Own tables: traits per character and the hidden values of evidence bags.
-- Hidden values are NOT in item metadata, because every client can read metadata.
WhipEvidence.Data = {}

local TRAITS = 'whip_evidence_traits'
local BAGS   = 'whip_evidence_bags'
local GUNS   = 'whip_evidence_weapon_prints'
local GROUND = 'whip_evidence_ground'
local PHOTOS = 'whip_evidence_photos'

local traitCache = {}   -- [charId] = { fingerprint, blood }
local ready = false

local BLOOD = { 'A+', 'A+', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O+', 'O+', 'O-' }
local CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'

local function marks(n)
    local list = {}
    for i = 1, n do list[i] = '?' end
    return table.concat(list, ',')
end

local function randomString(len)
    local out = {}
    for i = 1, len do
        local n = math.random(1, #CHARS)
        out[i] = CHARS:sub(n, n)
    end
    return table.concat(out)
end

function WhipEvidence.Data.newId()
    return randomString(10)
end

function WhipEvidence.Data.setup()
    local ok, why = Whip.core:EnsureTable(TRAITS, [[CREATE TABLE IF NOT EXISTS `whip_evidence_traits` (
        `charId` INT NOT NULL,
        `fingerprint` VARCHAR(32) NOT NULL,
        `blood` VARCHAR(4) NOT NULL,
        PRIMARY KEY (`charId`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table %s: %s', TRAITS, tostring(why)) end

    ok, why = Whip.core:EnsureTable(BAGS, [[CREATE TABLE IF NOT EXISTS `whip_evidence_bags` (
        `id` VARCHAR(16) NOT NULL,
        `kind` VARCHAR(24) NOT NULL,
        `secret` LONGTEXT NOT NULL,
        `analysed` TINYINT(1) NOT NULL DEFAULT 0,
        `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table %s: %s', BAGS, tostring(why)) end

    ok, why = Whip.core:EnsureTable(GUNS, [[CREATE TABLE IF NOT EXISTS `whip_evidence_weapon_prints` (
        `serial` VARCHAR(32) NOT NULL,
        `charId` INT NOT NULL,
        `touched` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`serial`, `charId`),
        KEY `touched` (`touched`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table %s: %s', GUNS, tostring(why)) end

    ok, why = Whip.core:EnsureTable(GROUND, [[CREATE TABLE IF NOT EXISTS `whip_evidence_ground` (
        `id` VARCHAR(16) NOT NULL,
        `kind` VARCHAR(24) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `heading` FLOAT NOT NULL DEFAULT 0,
        `origin` VARCHAR(64) NULL,
        `created` INT UNSIGNED NOT NULL,
        `expires` INT UNSIGNED NOT NULL,
        `reduced` TINYINT(1) NOT NULL DEFAULT 0,
        `fails` TINYINT UNSIGNED NOT NULL DEFAULT 0,
        `laser` INT NULL,
        `data` TEXT NOT NULL,
        PRIMARY KEY (`id`),
        KEY `expires` (`expires`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table %s: %s', GROUND, tostring(why)) end

    -- crime scene photos: the picture itself (the item only holds its id)
    ok, why = Whip.core:EnsureTable(PHOTOS, [[CREATE TABLE IF NOT EXISTS `whip_evidence_photos` (
        `id` VARCHAR(16) NOT NULL,
        `charId` INT NOT NULL,
        `image` MEDIUMTEXT NOT NULL,
        `created` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`id`),
        KEY `created` (`created`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table %s: %s', PHOTOS, tostring(why)) end

    -- case lockers (MDT upload): one row per case, one row per slot
    ok, why = Whip.core:EnsureTable('whip_evidence_cases', [[CREATE TABLE IF NOT EXISTS `whip_evidence_cases` (
        `id` VARCHAR(32) NOT NULL,
        `created` INT UNSIGNED NOT NULL,
        `closed` TINYINT(1) NOT NULL DEFAULT 0,
        `closed_by` VARCHAR(64) NULL,
        `taken` MEDIUMTEXT NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table whip_evidence_cases: %s', tostring(why)) end
    ok, why = Whip.core:EnsureTable('whip_evidence_case_items', [[CREATE TABLE IF NOT EXISTS `whip_evidence_case_items` (
        `case_id` VARCHAR(32) NOT NULL,
        `slot` SMALLINT UNSIGNED NOT NULL,
        `item` VARCHAR(50) NOT NULL,
        `amount` INT UNSIGNED NOT NULL DEFAULT 1,
        `metadata` MEDIUMTEXT NULL,
        PRIMARY KEY (`case_id`, `slot`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table whip_evidence_case_items: %s', tostring(why)) end

    -- filed serial numbers: what the weapon showed before (the lab gets part of it back)
    ok, why = Whip.core:EnsureTable('whip_evidence_filed', [[CREATE TABLE IF NOT EXISTS `whip_evidence_filed` (
        `filed` VARCHAR(32) NOT NULL,
        `original` VARCHAR(32) NOT NULL,
        `created` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`filed`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table whip_evidence_filed: %s', tostring(why)) end

    -- post-mortem reports (GetBodyReport still finds them after the body is gone)
    ok, why = Whip.core:EnsureTable('whip_evidence_reports', [[CREATE TABLE IF NOT EXISTS `whip_evidence_reports` (
        `id` VARCHAR(32) NOT NULL,
        `report` MEDIUMTEXT NOT NULL,
        `created` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not ok then return Whip.startProblem('table whip_evidence_reports: %s', tostring(why)) end
    if (Config.BodyReportDays or 0) > 0 then
        MySQL.update.await('DELETE FROM `whip_evidence_reports` WHERE `created` < ?', { os.time() - Config.BodyReportDays * 86400 })
    end

    -- old pictures go, except those of a case (in its locker, or taken out of it)
    if (Config.Photo.KeepDays or 0) > 0 then
        local gone = MySQL.update.await([[DELETE FROM `whip_evidence_photos` WHERE `created` < ?
            AND NOT EXISTS (SELECT 1 FROM `whip_evidence_case_items` c
                WHERE c.`item` = ? AND JSON_UNQUOTE(JSON_EXTRACT(c.`metadata`, '$.photo_id')) = `whip_evidence_photos`.`id`)
            AND NOT EXISTS (SELECT 1 FROM `whip_evidence_cases` k
                WHERE k.`taken` LIKE CONCAT('%"photo:', `whip_evidence_photos`.`id`, '"%'))]],
            { os.time() - Config.Photo.KeepDays * 86400, WhipEvidence.Items.photo })
        if (gone or 0) > 0 then print(('[%s] %d old photo(s) deleted'):format(WhipEvidence.Res, gone)) end
    end

    -- old weapon prints are useless: clear them once per start
    MySQL.update.await('DELETE FROM `whip_evidence_weapon_prints` WHERE `touched` < ?',
        { os.time() - Config.WeaponPrintHours * 3600 })

    ready = true
end

---------------------------------------------------------------- Ground evidence (survives restarts)

-- Every row that has not expired yet; expired rows are deleted
function WhipEvidence.Data.loadGround()
    if not ready then return {} end
    local now = os.time()
    MySQL.update.await('DELETE FROM `whip_evidence_ground` WHERE `expires` <= ?', { now })
    return MySQL.query.await('SELECT * FROM `whip_evidence_ground`') or {}
end

-- Writes changed evidence and deletes removed ids in one transaction (called in batches)
function WhipEvidence.Data.saveGround(rows, removed)
    if not ready or (#rows == 0 and #removed == 0) then return end
    local queries = {}
    if #rows > 0 then
        local marksList, values = {}, {}
        for _, r in ipairs(rows) do
            marksList[#marksList + 1] = '(?,?,?,?,?,?,?,?,?,?,?,?,?)'
            for _, v in ipairs({ r.id, r.kind, r.x, r.y, r.z, r.heading, r.origin, r.created, r.expires, r.reduced, r.fails, r.laser, r.data }) do
                values[#values + 1] = v
            end
        end
        queries[#queries + 1] = {
            query = 'INSERT INTO `whip_evidence_ground` (`id`,`kind`,`x`,`y`,`z`,`heading`,`origin`,`created`,`expires`,`reduced`,`fails`,`laser`,`data`) VALUES '
                .. table.concat(marksList, ',')
                .. ' ON DUPLICATE KEY UPDATE `expires` = VALUES(`expires`), `reduced` = VALUES(`reduced`), `fails` = VALUES(`fails`), '
                .. '`laser` = VALUES(`laser`), `created` = VALUES(`created`), `data` = VALUES(`data`)',
            values = values,
        }
    end
    if #removed > 0 then
        queries[#queries + 1] = {
            query = ('DELETE FROM `whip_evidence_ground` WHERE `id` IN (%s)'):format(marks(#removed)),
            values = removed,
        }
    end
    MySQL.transaction.await(queries)
end

---------------------------------------------------------------- Prints on weapons

function WhipEvidence.Data.touchWeapon(serial, charId)
    if not ready then return end
    MySQL.insert.await('INSERT INTO `whip_evidence_weapon_prints` (`serial`, `charId`, `touched`) VALUES (?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE `touched` = VALUES(`touched`)', { serial, charId, os.time() })
end

-- charIds whose prints are still on this weapon
function WhipEvidence.Data.weaponPrints(serial)
    if not ready then return {} end
    local rows = MySQL.query.await('SELECT `charId` FROM `whip_evidence_weapon_prints` WHERE `serial` = ? AND `touched` >= ?',
        { serial, os.time() - Config.WeaponPrintHours * 3600 }) or {}
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = row.charId end
    return out
end

function WhipEvidence.Data.wipeWeapon(serial)
    if not ready then return 0 end
    return MySQL.update.await('DELETE FROM `whip_evidence_weapon_prints` WHERE `serial` = ?', { serial }) or 0
end

---------------------------------------------------------------- Filed serial numbers

-- Remembers the original, and moves the prints on the weapon to its new (filed) serial
function WhipEvidence.Data.fileSerial(filed, original)
    if not ready then return false end
    return MySQL.transaction.await({
        { query = 'INSERT INTO `whip_evidence_filed` (`filed`, `original`, `created`) VALUES (?, ?, ?)', values = { filed, original, os.time() } },
        { query = 'UPDATE IGNORE `whip_evidence_weapon_prints` SET `serial` = ? WHERE `serial` = ?', values = { filed, original } },
    })
end

-- A body's post-mortem report (json); saved again when the body goes, so the last state is kept
function WhipEvidence.Data.saveReport(id, report, created)
    if not ready then return end
    MySQL.insert('INSERT INTO `whip_evidence_reports` (`id`, `report`, `created`) VALUES (?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE `report` = VALUES(`report`)', { id, report, created or os.time() })
end

function WhipEvidence.Data.loadReport(id)
    if not ready then return nil end
    return MySQL.scalar.await('SELECT `report` FROM `whip_evidence_reports` WHERE `id` = ?', { id })
end

function WhipEvidence.Data.filedOriginal(filed)
    if not ready then return nil end
    return MySQL.scalar.await('SELECT `original` FROM `whip_evidence_filed` WHERE `filed` = ?', { filed })
end

-- Fingerprint and blood type of a character (online or offline). Waits on the DB.
function WhipEvidence.Data.traits(charId)
    if not charId then return nil end
    if traitCache[charId] then return traitCache[charId] end
    if not ready then return nil end

    local row = MySQL.single.await('SELECT `fingerprint`, `blood` FROM `whip_evidence_traits` WHERE `charId` = ?', { charId })
    if not row then
        row = { fingerprint = randomString(12), blood = BLOOD[math.random(1, #BLOOD)] }
        MySQL.insert.await('INSERT IGNORE INTO `whip_evidence_traits` (`charId`, `fingerprint`, `blood`) VALUES (?, ?, ?)',
            { charId, row.fingerprint, row.blood })
        -- someone may have written at the same time: use what is stored
        row = MySQL.single.await('SELECT `fingerprint`, `blood` FROM `whip_evidence_traits` WHERE `charId` = ?', { charId }) or row
    end
    traitCache[charId] = { fingerprint = row.fingerprint, blood = row.blood }
    return traitCache[charId]
end

function WhipEvidence.Data.forget(charId)
    traitCache[charId] = nil
end

-- Query for CommitWithAction: lands in the same transaction as the item
function WhipEvidence.Data.bagQuery(id, kind, secret)
    return {
        query  = 'INSERT INTO `whip_evidence_bags` (`id`, `kind`, `secret`) VALUES (?, ?, ?)',
        values = { id, kind, json.encode(secret or {}) },
    }
end

-- Saves bag rows with the item change. If that transaction fails, the rows are written on their own,
-- so a bag never ends up without its hidden values (the lab would not see it).
function WhipEvidence.Data.saveBags(queries)
    if #queries == 0 then return true end
    local ok, why = exports.whip_core:CommitWithAction(queries)
    if ok then return true end
    WhipEvidence.debug('CommitWithAction failed (%s), writing bag rows directly', tostring(why))
    for _, q in ipairs(queries) do
        MySQL.insert.await((q.query:gsub('^INSERT INTO', 'INSERT IGNORE INTO')), q.values)
    end
    return true
end

-- State of bags by id: { [id] = { analysed = bool } } (missing = no row)
function WhipEvidence.Data.bagStates(ids)
    local out = {}
    if #ids == 0 then return out end
    local list = {}
    for i = 1, #ids do list[i] = '?' end
    local rows = MySQL.query.await(('SELECT `id`, `analysed` FROM `whip_evidence_bags` WHERE `id` IN (%s)')
        :format(table.concat(list, ',')), ids) or {}
    for _, row in ipairs(rows) do out[row.id] = { analysed = row.analysed == 1 or row.analysed == true } end
    return out
end

-- Hidden values of bags that are not analysed yet: { [id] = secret }
function WhipEvidence.Data.pendingSecrets(ids)
    local out = {}
    if #ids == 0 then return out end
    local rows = MySQL.query.await(('SELECT `id`, `secret` FROM `whip_evidence_bags` WHERE `analysed` = 0 AND `id` IN (%s)')
        :format(marks(#ids)), ids) or {}
    for _, row in ipairs(rows) do
        out[row.id] = json.decode(row.secret) or {}
    end
    return out
end

function WhipEvidence.Data.markAnalysed(ids)
    if #ids == 0 then return end
    MySQL.update.await(('UPDATE `whip_evidence_bags` SET `analysed` = 1 WHERE `id` IN (%s)'):format(marks(#ids)), ids)
end

---------------------------------------------------------------- Photos

function WhipEvidence.Data.savePhoto(id, charId, image)
    if not ready then return false end
    return MySQL.insert.await('INSERT IGNORE INTO `whip_evidence_photos` (`id`, `charId`, `image`, `created`) VALUES (?, ?, ?, ?)',
        { id, charId, image, os.time() }) ~= nil
end

function WhipEvidence.Data.loadPhoto(id)
    if not ready or type(id) ~= 'string' then return nil end
    return MySQL.scalar.await('SELECT `image` FROM `whip_evidence_photos` WHERE `id` = ?', { id })
end

---------------------------------------------------------------- Case lockers

function WhipEvidence.Data.loadCases()
    if not ready then return {}, {} end
    return MySQL.query.await('SELECT * FROM `whip_evidence_cases`') or {},
           MySQL.query.await('SELECT * FROM `whip_evidence_case_items`') or {}
end

function WhipEvidence.Data.saveCase(c)
    if not ready then return end
    MySQL.prepare('INSERT INTO `whip_evidence_cases` (`id`, `created`, `closed`, `closed_by`, `taken`) VALUES (?, ?, ?, ?, ?) '
        .. 'ON DUPLICATE KEY UPDATE `closed` = VALUES(`closed`), `closed_by` = VALUES(`closed_by`), `taken` = VALUES(`taken`)',
        { c.id, c.created, c.closed and 1 or 0, c.closedBy, json.encode(c.taken or {}) })
end
