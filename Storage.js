// Storage.js - 文件持久化存储（主）+ SQLite（备）

var BACKUP_PATH = "/userdisk/.novel-reader-state.json";
var dataCache = null;   // 内存缓存 {key: value}
var sqliteDb = null;    // SQLite 备选存储

// ====== 初始化 ======

function openDatabase() {
    // 打开 SQLite 作为备选
    try {
        sqliteDb = Qt.openDatabaseSync("NovelReaderStateV2", "1.0", "Novel Reader State", 1000000);
        sqliteDb.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT)");
        });
    } catch (e) {
        sqliteDb = null;
    }
    // 从备份文件加载到内存缓存
    loadFileCache();
    return sqliteDb;
}

// ====== 文件读写（主存储） ======

function loadFileCache() {
    dataCache = {};
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + BACKUP_PATH, false);
        xhr.send();
        if (xhr.status === 200 || xhr.status === 0) {
            var parsed = JSON.parse(xhr.responseText);
            if (parsed && typeof parsed === "object")
                dataCache = parsed;
        }
    } catch (e) {}
}

function flushToFile() {
    var ctrl = getShellCtrl();
    if (!ctrl) return;
    try {
        var json = JSON.stringify(dataCache);
        var b64 = Qt.btoa(json);
        ctrl.sendCommand("echo " + b64 + " | base64 -d > " + BACKUP_PATH + " 2>/dev/null");
    } catch (e) {}
}

function getShellCtrl() {
    return (typeof shellPluginController !== "undefined") ? shellPluginController : null;
}

// ====== 键值读写（缓存 + 文件 + SQLite 三重保障） ======

function readState(db, key, fallbackValue) {
    if (dataCache === null) loadFileCache();
    return dataCache.hasOwnProperty(key) ? dataCache[key] : fallbackValue;
}

function writeState(db, key, value) {
    if (dataCache === null) loadFileCache();
    dataCache[key] = value;
    // 写入备份文件
    flushToFile();
    // 也写入 SQLite 作为备选
    if (sqliteDb) {
        try {
            sqliteDb.transaction(function (tx) {
                tx.executeSql("INSERT OR REPLACE INTO state(key, value) VALUES(?, ?)", [key, value]);
            });
        } catch (e) {}
    }
    return true;
}

// ====== 进度/书签/设置 读写（保持 API 不变） ======

function loadProgressStore(db) {
    try {
        return JSON.parse(readState(db, "progress", "{}")) || {};
    } catch (e) {
        return {};
    }
}

function loadBookmarksStore(db) {
    try {
        return JSON.parse(readState(db, "bookmarks", "{}")) || {};
    } catch (e) {
        return {};
    }
}

function loadSettingsFromStore(db) {
    var settings = {};
    try {
        settings = JSON.parse(readState(db, "settings", "{}")) || {};
    } catch (e) {
        settings = {};
    }
    return settings;
}

function saveSettingsToStore(db, settings) {
    writeState(db, "settings", JSON.stringify(settings));
}

function updateProgressMemory(progressStore, currentUrl, fileName, currentLine, totalLines) {
    if (currentUrl === "") return;
    progressStore[currentUrl] = {
        file: currentUrl,
        name: fileName,
        line: currentLine,
        totalLines: totalLines,
        timestamp: new Date().getTime()
    };
}

function flushProgressToDB(db, progressStore) {
    writeState(db, "progress", JSON.stringify(progressStore));
}

function saveProgressToStore(db, currentUrl, fileName, currentLine, lines, progressStore) {
    if (currentUrl === "") return;
    updateProgressMemory(progressStore, currentUrl, fileName, currentLine, lines.length);
    writeState(db, "progress", JSON.stringify(progressStore));
}

function loadProgressFromStore(progressStore, url) {
    var item = progressStore[url];
    return item ? (parseInt(item.line) || 0) : 0;
}

function deleteRecord(db, currentUrl, progressStore) {
    if (currentUrl === "") return false;
    delete progressStore[currentUrl];
    return writeState(db, "progress", JSON.stringify(progressStore));
}
