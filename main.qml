import QtQuick 2.15
import QtQuick.LocalStorage 2.0
import "qrc:/qml/commons"

Rectangle {
    id: root
    width: 320
    height: 170
    color: bgColor

    signal backButtonClicked()

    property string currentUrl: ""
    property string fileName: ""
    property bool isLoading: false
    property string statusMessage: ""
    property var xhr: null
    property int currentRequestId: 0

    property var lines: []
    property int currentLine: 0
    property int charsPerLine: 35
    property var chapterList: []

    property int baseFontSize: 14
    property int lineSpacing: 4
    property string bgColor: "#FFFBF0"
    property string textColor: "#333333"
    property string themeName: "默认"
    property bool autoScroll: false
    property int autoScrollSeconds: 2

    property string activePanel: ""
    property string homeMode: "home"
    property bool keyboardPending: false
    property real pendingProgressRatio: -1
    property var bookList: []
    property var bookmarkList: []
    property var progressStore: ({})
    property var bookmarksStore: ({})
    property string lastFilePath: ""
    property var bookFolderModel: null
    property bool folderScanAvailable: false
    property var uploaderController: (typeof shellPluginController !== "undefined") ? shellPluginController : null
    property bool uploaderStarted: false
    property string uploaderStatus: "上传服务未启动"
    property string uploaderAddress: ""
    property string uploaderOutput: ""
    property var db: null
    property bool showSponsor: false
    property int sponsorQrIndex: 0
    property bool showTutorial: false
    property int tutorialLine: 0
    property var tutorialLines: []
    readonly property string defaultBookFolder: "/userdisk/Music/"
    readonly property string defaultBookSuffix: ".txt"
    readonly property int readerMargin: 6

    FontMetrics {
        id: readerFontMetrics
        font.pixelSize: baseFontSize
    }

    Timer {
        id: autoScrollTimer
        interval: Math.max(1, autoScrollSeconds) * 1000
        repeat: true
        running: autoScroll && currentUrl !== "" && activePanel === ""
        onTriggered: nextPage()
    }

    Timer {
        id: uploaderStartTimer
        interval: 700
        repeat: false
        onTriggered: startUploaderService()
    }

    Timer {
        id: uploaderOutputTimer
        interval: 500
        repeat: true
        running: true
        onTriggered: refreshUploaderOutput()
    }

    Component.onCompleted: {
        initDatabase()
        uploaderStartTimer.start()
        var everOpened = readState("everOpened", "")
        if (everOpened === "") {
            writeState("everOpened", "1")
            sponsorQrIndex = 0
            showSponsor = true
        }
    }

    Component.onDestruction: {
        saveProgress()
        saveSettings()
    }

    function initDatabase() {
        try {
            db = LocalStorage.openDatabaseSync("NovelReaderStateV2", "1.0", "Novel Reader State", 1000000)
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT)")
            })
        } catch (e) {
            db = null
        }
        loadSettings()
        loadProgressStore()
        loadBookmarksStore()
        startBookFolderScan()
        loadBookList()
    }

    function startUploaderService() {
        if (uploaderStarted) return
        uploaderController = (typeof shellPluginController !== "undefined") ? shellPluginController : null
        if (!uploaderController) {
            uploaderStatus = "上传服务未加载"
            return
        }

        uploaderStarted = true
        uploaderStatus = "上传服务启动中"
        uploaderAddress = ""
        uploaderController.startShell()
        uploaderController.sendCommand("sh /userdisk/PenMods/plugins/novel-reader/start-uploader.sh || sh /userdisk/youdaoExt/ext/novel-reader/start-uploader.sh || sh ./start-uploader.sh")
    }

    function stopUploaderService() {
        if (!uploaderStarted) return
        if (uploaderController) {
            uploaderController.sendCommand("kill $(lsof -t -i:8088) 2>/dev/null; pkill -f uploader.py; pkill -f uploader.js; echo '上传服务已停止'")
        }
        uploaderStarted = false
        uploaderStatus = "上传服务已停止"
        uploaderAddress = ""
    }

    function openShelf() {
        homeMode = "shelf"
        loadBookList()
    }

    function closeShelf() {
        homeMode = "home"
    }

    function openTutorial() {
        tutorialLines = [
            "【使用教程】",
            "",
            "一、小说存放位置",
            "小说文件请放到：",
            "/userdisk/Music/",
            "支持 .txt 格式，文件名随意。",
            "",
            "二、打开小说",
            "1. 自动扫描：把 txt 放到上面的目录后，",
            "   进入「我的书架」即可看到。",
            "2. 手动输入：首页点击「手动输入书名」，",
            "   输入小说名即可，不需要输完整路径。",
            "",
            "三、上传小说",
            "1. 局域网上传（推荐）：",
            "   点击「启动上传」，首页会显示一个网址，",
            "   手机/电脑浏览器打开该网址即可上传。",
            "   手机和词典笔需连接同一个 Wi-Fi。",
            "2. SSH 上传：",
            "   用 WinSCP（电脑）或 Termius（手机）",
            "   通过 SFTP 连接词典笔，",
            "   把 txt 文件传到 /userdisk/Music/。",
            "   连接信息：IP:词典笔IP 端口:22",
            "   用户名:root 密码:PenMods中设置的SSH密码",
            "",
            "四、阅读操作",
            "· 点击屏幕左侧 1/3：上一页",
            "· 点击屏幕右侧 1/3：下一页",
            "· 点击屏幕中间 1/3：打开菜单",
            "· 上下左右滑动：翻页",
            "",
            "五、菜单功能",
            "· 进度条：拖拽快速跳转",
            "· 字号：小/中/大 三档",
            "· 行距：紧凑/标准/宽松",
            "· 主题：7种配色可选",
            "· 书签：添加/查看/删除书签",
            "· 跳转：按百分比/页码/章节跳转",
            "· 自动翻页：可自定义间隔秒数",
            "· 上一章/下一章：快速切换章节",
            "",
            "六、常见问题",
            "Q: 书架没有显示小说？",
            "A: 确认文件在 /userdisk/Music/ 且后缀是 .txt",
            "",
            "Q: 上传网页打不开？",
            "A: 确认手机和词典笔在同一 Wi-Fi，",
            "   并检查词典笔系统是否有 python3 或 node。",
            "",
            "Q: 手动输入书名打不开？",
            "A: 只需输入小说名，如「三体」，",
            "   不需要输入完整路径。",
            "",
            "【以上为全部教程内容】"
        ]
        tutorialLine = 0
        showTutorial = true
    }

    function refreshUploaderOutput() {
        if (!uploaderStarted) return
        uploaderController = (typeof shellPluginController !== "undefined") ? shellPluginController : null
        uploaderOutput = uploaderController ? uploaderController.outputText : ""
        var match = uploaderOutput.match(/http:\/\/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8088/)
        if (match && match.length > 0) {
            uploaderAddress = match[0]
            uploaderStatus = "上传服务已启动"
        } else if (uploaderStarted && uploaderOutput.indexOf("未找到 python3 或 node") >= 0) {
            uploaderStatus = "缺少 python3/node"
        } else if (uploaderStarted && uploaderOutput.indexOf("Address already in use") >= 0) {
            uploaderStatus = "端口已占用"
        }
    }

    function readState(key, fallbackValue) {
        if (!db) return fallbackValue
        var result = fallbackValue
        try {
            db.transaction(function(tx) {
                var rs = tx.executeSql("SELECT value FROM state WHERE key = ?", [key])
                if (rs.rows.length > 0) result = rs.rows.item(0).value
            })
        } catch (e) {
            result = fallbackValue
        }
        return result
    }

    function writeState(key, value) {
        if (!db) return false
        try {
            db.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT)")
                tx.executeSql("INSERT OR REPLACE INTO state(key, value) VALUES(?, ?)", [key, value])
            })
            return true
        } catch (e) {
            return false
        }
    }

    function loadProgressStore() {
        try {
            progressStore = JSON.parse(readState("progress", "{}")) || {}
        } catch (e) {
            progressStore = {}
        }
    }

    function loadBookmarksStore() {
        try {
            bookmarksStore = JSON.parse(readState("bookmarks", "{}")) || {}
        } catch (e) {
            bookmarksStore = {}
        }
    }

    function saveProgress() {
        if (!db || currentUrl === "") return
        progressStore[currentUrl] = {
            file: currentUrl,
            name: fileName || bookTitle(currentUrl),
            line: currentLine,
            totalLines: lines.length,
            timestamp: new Date().getTime()
        }
        writeState("progress", JSON.stringify(progressStore))
    }

    function loadProgress(url) {
        var item = progressStore[url]
        return item ? (parseInt(item.line) || 0) : 0
    }

    function saveSettings() {
        var settings = {
            fontSize: baseFontSize,
            lineSpacing: lineSpacing,
            bgColor: bgColor,
            textColor: textColor,
            themeName: themeName,
            lastFile: lastFilePath,
            autoScrollSeconds: autoScrollSeconds
        }
        writeState("settings", JSON.stringify(settings))
    }

    function loadSettings() {
        var settings = {}
        try {
            settings = JSON.parse(readState("settings", "{}")) || {}
        } catch (e) {
            settings = {}
        }
        baseFontSize = parseInt(settings.fontSize) || 14
        lineSpacing = parseInt(settings.lineSpacing) || 4
        bgColor = settings.bgColor || "#FFFBF0"
        textColor = settings.textColor || "#333333"
        themeName = settings.themeName || "默认"
        lastFilePath = settings.lastFile || ""
        if (settings.autoScrollSeconds !== undefined) {
            autoScrollSeconds = normalizeAutoScrollSeconds(settings.autoScrollSeconds)
        } else if (settings.autoScrollSpeed !== undefined) {
            var oldSpeed = parseInt(settings.autoScrollSpeed) || 3
            autoScrollSeconds = normalizeAutoScrollSeconds(Math.round(2 / Math.max(1, oldSpeed)))
        } else {
            autoScrollSeconds = 2
        }
        updateCharsPerLine()
    }

    function loadBookList() {
        var items = []
        var seen = {}

        if (folderScanAvailable && bookFolderModel) {
            for (var i = 0; i < bookFolderModel.count; i++) {
                var url = folderModelFileUrl(i)
                if (url === "") continue
                seen[url] = true

                var progressItem = progressStore[url] || {}
                var line = parseInt(progressItem.line) || 0
                var totalLines = parseInt(progressItem.totalLines) || 0
                items.push({
                    file: url,
                    name: bookTitle(url),
                    line: line,
                    totalLines: totalLines,
                    timestamp: parseInt(progressItem.timestamp) || 0,
                    progress: progressFromLine(line, totalLines)
                })
            }
        }

        for (var file in progressStore) {
            if (seen[file]) continue
            var item = progressStore[file]
            var itemFile = item.file || file
            if (folderScanAvailable && isDefaultBookFile(itemFile)) continue
            items.push({
                file: itemFile,
                name: bookTitle(item.name || itemFile),
                line: parseInt(item.line) || 0,
                totalLines: parseInt(item.totalLines) || 0,
                timestamp: parseInt(item.timestamp) || 0,
                progress: progressFromLine(parseInt(item.line) || 0, parseInt(item.totalLines) || 0)
            })
        }
        items.sort(function(a, b) {
            if (a.timestamp !== b.timestamp) return b.timestamp - a.timestamp
            return a.name.localeCompare(b.name)
        })
        if (items.length > 50) items = items.slice(0, 50)
        bookList = items
    }

    function startBookFolderScan() {
        if (bookFolderModel) return
        try {
            var qml = "import QtQuick 2.15\n"
                    + "import Qt.labs.folderlistmodel 2.1\n"
                    + "FolderListModel {\n"
                    + "    folder: \"file://" + defaultBookFolder + "\"\n"
                    + "    nameFilters: [\"*.txt\", \"*.TXT\"]\n"
                    + "    showDirs: false\n"
                    + "    showFiles: true\n"
                    + "    showDotAndDotDot: false\n"
                    + "    sortField: FolderListModel.Name\n"
                    + "}\n"
            bookFolderModel = Qt.createQmlObject(qml, root, "BookFolderModel")
            bookFolderModel.countChanged.connect(loadBookList)
            folderScanAvailable = true
            loadBookList()
        } catch (e) {
            bookFolderModel = null
            folderScanAvailable = false
        }
    }

    function folderModelFileUrl(index) {
        if (!bookFolderModel) return ""
        var fileName = bookFolderModel.get(index, "fileName")
        if (fileName) return addFilePrefix(defaultBookFolder + String(fileName))
        var fileUrl = bookFolderModel.get(index, "fileURL")
        if (fileUrl) return String(fileUrl)
        var filePath = bookFolderModel.get(index, "filePath")
        if (filePath) return addFilePrefix(String(filePath))
        return ""
    }

    function loadBookmarkList() {
        if (currentUrl === "") {
            bookmarkList = []
            return
        }
        var items = bookmarksStore[currentUrl] || []
        items.sort(function(a, b) { return (parseInt(a.line) || 0) - (parseInt(b.line) || 0) })
        bookmarkList = items
    }

    function addBookmark() {
        if (currentUrl === "") return
        var preview = lines.length > currentLine ? String(lines[currentLine]).trim() : ""
        if (preview.length > 22) preview = preview.substring(0, 22) + "..."

        var items = bookmarksStore[currentUrl] || []
        items.push({
            id: String(new Date().getTime()) + "_" + String(Math.floor(Math.random() * 10000)),
            file: currentUrl,
            name: fileName,
            line: currentLine,
            percent: getProgressPercent(),
            preview: preview
        })
        bookmarksStore[currentUrl] = items
        if (writeState("bookmarks", JSON.stringify(bookmarksStore))) {
            loadBookmarkList()
            statusMessage = "已添加书签"
            messageTimer.restart()
        } else {
            statusMessage = "添加书签失败"
            messageTimer.restart()
        }
    }

    function deleteBookmark(id) {
        if (currentUrl === "") return
        var source = bookmarksStore[currentUrl] || []
        var kept = []
        for (var i = 0; i < source.length; i++) {
            if (source[i].id !== id) kept.push(source[i])
        }
        bookmarksStore[currentUrl] = kept
        if (writeState("bookmarks", JSON.stringify(bookmarksStore))) {
            loadBookmarkList()
        } else {
            statusMessage = "删除书签失败"
            messageTimer.restart()
        }
    }

    function deleteCurrentRecord() {
        if (!db || currentUrl === "") return
        delete progressStore[currentUrl]
        if (writeState("progress", JSON.stringify(progressStore))) {
            statusMessage = "记录已删除"
            messageTimer.restart()
            loadBookList()
        } else {
            statusMessage = "删除记录失败"
            messageTimer.restart()
        }
    }

    function basename(url) {
        if (typeof url !== "string") return "未命名"
        var parts = url.replace(/\\/g, "/").split("/")
        return parts[parts.length - 1] || "未命名"
    }

    function bookTitle(value) {
        var name = basename(value)
        try {
            name = decodeURIComponent(name)
        } catch (e) {}
        var lower = name.toLowerCase()
        if (lower.length > defaultBookSuffix.length
                && lower.substring(lower.length - defaultBookSuffix.length) === defaultBookSuffix) {
            name = name.substring(0, name.length - defaultBookSuffix.length)
        }
        return name
    }

    function stripFilePrefix(url) {
        if (typeof url !== "string") return ""
        return url.indexOf("file://") === 0 ? url.substring(7) : url
    }

    function isDefaultBookFile(url) {
        var path = stripFilePrefix(url).replace(/\\/g, "/")
        try {
            path = decodeURIComponent(path)
        } catch (e) {}
        return path.toLowerCase().indexOf(defaultBookFolder.toLowerCase()) === 0
    }

    function addFilePrefix(path) {
        if (typeof path !== "string") return ""
        path = path.trim()
        if (path === "") return ""
        if (path.indexOf("file://") === 0) return path
        return "file://" + path
    }

    function normalizeBookInput(text) {
        if (typeof text !== "string") return ""
        var path = text.trim()
        if (path === "") return ""
        if (path.indexOf("file://") === 0) return path

        var hasFolder = path.indexOf("/") >= 0 || path.indexOf("\\") >= 0
        if (!hasFolder) {
            var lower = path.toLowerCase()
            if (lower.length < defaultBookSuffix.length
                    || lower.substring(lower.length - defaultBookSuffix.length) !== defaultBookSuffix) {
                path += defaultBookSuffix
            }
            path = defaultBookFolder + path
        }
        return addFilePrefix(path)
    }

    function encodePath(url) {
        if (url.indexOf("file://") !== 0) return url
        var p = url.substring(7)
        var encoded = ""
        for (var i = 0; i < p.length; i++) {
            var c = p.charAt(i)
            encoded += c.charCodeAt(0) > 127 ? encodeURIComponent(c) : c
        }
        return "file://" + encoded
    }

    function updateCharsPerLine() {
        if (baseFontSize <= 13) charsPerLine = 22
        else if (baseFontSize <= 15) charsPerLine = 19
        else charsPerLine = 16
    }

    function progressFromLine(line, total) {
        if (line <= 0) return 0
        if (total > 0) return Math.min(100, Math.max(1, Math.round((line / total) * 100)))
        return Math.min(99, Math.max(1, Math.round(line / 100)))
    }

    function normalizeAutoScrollSeconds(value) {
        var seconds = parseInt(value)
        if (isNaN(seconds)) seconds = 2
        return Math.max(1, Math.min(999, seconds))
    }

    function getLinesPerPage() {
        var readableHeight = Math.max(40, root.height - readerMargin * 2)
        return Math.max(1, Math.floor(readableHeight / getTextLineHeight()))
    }

    function getTextLineHeight() {
        var extraSpacing = baseFontSize <= 13 ? Math.max(0, lineSpacing - 2) : lineSpacing
        return Math.max(1, Math.ceil(readerFontMetrics.height) + extraSpacing)
    }

    function maxStartLine() {
        return Math.max(0, lines.length - getLinesPerPage())
    }

    function clampCurrentLine() {
        currentLine = Math.max(0, Math.min(currentLine, maxStartLine()))
    }

    function getProgressPercent() {
        if (lines.length === 0) return 0
        return Math.round((currentLine / lines.length) * 100)
    }

    function getCurrentPage() {
        return Math.floor(currentLine / getLinesPerPage()) + 1
    }

    function getTotalPages() {
        return Math.max(1, Math.ceil(lines.length / getLinesPerPage()))
    }

    function getPageText() {
        if (lines.length === 0) return ""
        var lpp = getLinesPerPage()
        var end = Math.min(currentLine + lpp, lines.length)
        var page = []
        for (var i = currentLine; i < end; i++) page.push(lines[i])
        return page.join("\n")
    }

    function closePanels() {
        activePanel = ""
    }

    function openPanel(name) {
        activePanel = name
        if (name === "bookmarks") loadBookmarkList()
    }

    function returnToShelf() {
        var oldUrl = currentUrl
        var oldName = fileName
        var oldLine = currentLine
        var oldTotalLines = lines.length

        autoScroll = false
        closePanels()
        homeMode = "shelf"
        currentUrl = ""
        fileName = ""
        lines = []
        chapterList = []
        bookmarkList = []
        currentLine = 0

        if (oldUrl === "") {
            loadBookList()
            return
        }

        progressStore[oldUrl] = {
            file: oldUrl,
            name: oldName || basename(oldUrl),
            line: oldLine,
            totalLines: oldTotalLines,
            timestamp: new Date().getTime()
        }
        writeState("progress", JSON.stringify(progressStore))
        loadBookList()
    }

    function loadFile(url) {
        if (!url) return
        if (xhr && xhr.readyState === XMLHttpRequest.LOADING) {
            xhr.abort()
            xhr = null
        }

        closePanels()
        isLoading = true
        statusMessage = ""
        currentUrl = url
        fileName = bookTitle(url)
        lastFilePath = url

        var encodedUrl = encodePath(url)
        doLoadFile(url, encodedUrl)
    }

    function doLoadFile(originalUrl, requestUrl) {
        var reqId = ++currentRequestId
        xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (reqId !== currentRequestId) return
            if (xhr.readyState !== XMLHttpRequest.DONE) return

            isLoading = false
            if (xhr.status === 200 || xhr.status === 0) {
                var content = xhr.responseText || ""
                if (content.length > 0 && content.charCodeAt(0) === 0xFEFF) content = content.substring(1)
                processContent(content)
                if (pendingProgressRatio >= 0) {
                    currentLine = Math.floor(pendingProgressRatio * lines.length)
                    pendingProgressRatio = -1
                } else {
                    currentLine = loadProgress(originalUrl)
                }
                clampCurrentLine()
                loadBookmarkList()
                saveSettings()
                statusMessage = ""
            } else if (requestUrl !== originalUrl) {
                doLoadFile(originalUrl, originalUrl)
                return
            } else {
                lines = []
                chapterList = []
                currentLine = 0
                statusMessage = "无法打开文件"
            }
            xhr = null
        }
        xhr.onerror = function() {
            if (requestUrl !== originalUrl) {
                doLoadFile(originalUrl, originalUrl)
                return
            }
            isLoading = false
            lines = []
            chapterList = []
            currentLine = 0
            statusMessage = "无法打开文件"
            xhr = null
        }
        xhr.open("GET", requestUrl)
        xhr.send()
    }

    function processContent(content) {
        var rawLines = content.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n")
        var wrapped = []
        var chapters = []
        var chapterRegex = /^(第[一二三四五六七八九十百千零\d]+[章节回集卷部篇]|Chapter\s+\d+|CHAPTER\s+\d+)/

        for (var i = 0; i < rawLines.length; i++) {
            var raw = rawLines[i]
            var title = raw.trim()
            if (title.length > 0 && title.length < 50 && chapterRegex.test(title)) {
                chapters.push({ title: title, lineIndex: wrapped.length })
            }

            if (raw.length === 0) {
                wrapped.push("")
            } else {
                var rest = raw
                while (rest.length > charsPerLine) {
                    wrapped.push(rest.substring(0, charsPerLine))
                    rest = rest.substring(charsPerLine)
                }
                wrapped.push(rest)
            }
        }

        lines = wrapped
        chapterList = chapters
    }

    function nextPage() {
        if (currentLine < maxStartLine()) {
            currentLine = Math.min(currentLine + getLinesPerPage(), maxStartLine())
            saveProgress()
        } else {
            autoScroll = false
        }
    }

    function prevPage() {
        if (currentLine > 0) {
            currentLine = Math.max(0, currentLine - getLinesPerPage())
            saveProgress()
        }
    }

    function jumpToPercent(percent) {
        if (lines.length === 0) return
        var lpp = getLinesPerPage()
        percent = Math.max(0, Math.min(100, percent))
        currentLine = Math.floor((percent / 100) * lines.length)
        clampCurrentLine()
        currentLine = Math.floor(currentLine / lpp) * lpp
        saveProgress()
    }

    function jumpToPage(page) {
        var lpp = getLinesPerPage()
        currentLine = (Math.max(1, page) - 1) * lpp
        clampCurrentLine()
        saveProgress()
    }

    function jumpToChapter(offset) {
        if (chapterList.length === 0) return
        var currentIndex = 0
        for (var i = 0; i < chapterList.length; i++) {
            if (chapterList[i].lineIndex <= currentLine) currentIndex = i
        }
        var nextIndex = Math.max(0, Math.min(chapterList.length - 1, currentIndex + offset))
        currentLine = chapterList[nextIndex].lineIndex
        saveProgress()
    }

    function setFontSize(size) {
        var ratio = lines.length > 0 ? currentLine / lines.length : 0
        baseFontSize = size
        updateCharsPerLine()
        if (currentUrl !== "") {
            pendingProgressRatio = ratio
            loadFile(currentUrl)
        }
        saveSettings()
    }

    function setTheme(name) {
        themeName = name
        if (name === "默认") { bgColor = "#FFFBF0"; textColor = "#333333" }
        else if (name === "白色") { bgColor = "#FFFFFF"; textColor = "#333333" }
        else if (name === "黄色") { bgColor = "#FFF8E1"; textColor = "#5D4037" }
        else if (name === "绿色") { bgColor = "#E8F5E9"; textColor = "#2E7D32" }
        else if (name === "黑色") { bgColor = "#263238"; textColor = "#ECEFF1" }
        else if (name === "粉色") { bgColor = "#FCE4EC"; textColor = "#880E4F" }
        else if (name === "蓝色") { bgColor = "#E3F2FD"; textColor = "#1565C0" }
        saveSettings()
    }

    function showKeyboard(initialText, callback) {
        if (keyboardPending) return
        if (typeof qmlGlobal !== "undefined" && qmlGlobal.inputPageShowing) return
        keyboardPending = true

        try {
            var comp = qmlCreateComponent("YInputPage")
            if (comp.status === Component.Ready) {
                var incubator = comp.incubateObject(pagePopHelper.containerItem)
                if (incubator.status !== Component.Ready) {
                    incubator.onStatusChanged = function(status) {
                        if (status === Component.Ready) setupKeyboard(incubator.object, initialText, callback)
                    }
                } else {
                    setupKeyboard(incubator.object, initialText, callback)
                }
            } else {
                keyboardPending = false
            }
        } catch (e) {
            keyboardPending = false
        }
    }

    function setupKeyboard(keyboardPage, initialText, callback) {
        keyboardPage.backButtonClicked.connect(function() {
            if (typeof qmlGlobal !== "undefined") qmlGlobal.inputPageShowing = false
            keyboardPage.todoDestroy()
            keyboardPending = false
        })
        keyboardPage.inputFinished.connect(function(content) {
            if (typeof qmlGlobal !== "undefined") qmlGlobal.inputPageShowing = false
            keyboardPage.todoDestroy()
            keyboardPending = false
            if (content !== undefined && callback) callback(content)
        })
        keyboardPage.enterText(initialText)
        keyboardPage.show()
        if (typeof qmlGlobal !== "undefined") qmlGlobal.inputPageShowing = true
    }

    Timer {
        id: messageTimer
        interval: 1200
        repeat: false
        onTriggered: statusMessage = ""
    }

    Item {
        id: homePage
        anchors.fill: parent
        visible: currentUrl === ""

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4
            visible: homeMode === "home"

            Text {
                width: parent.width
                text: "电子书阅读器"
                font.pixelSize: 16
                font.bold: true
                color: textColor
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: uploaderAddress !== "" ? uploaderAddress : "小说请放到 " + defaultBookFolder
                font.pixelSize: 10
                color: uploaderAddress !== "" ? "#1565C0" : textColor
                opacity: uploaderAddress !== "" ? 1.0 : 0.65
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: uploaderAddress !== "" ? "手机/电脑浏览器输入以上网址上传 txt" : uploaderStatus
                font.pixelSize: 9
                color: "#666666"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            Row {
                width: parent.width
                height: 24
                spacing: 6

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 24
                    radius: 3
                    color: uploaderStarted ? "#FFEBEE" : "#E3F2FD"
                    border.color: uploaderStarted ? "#EF9A9A" : "#BBDEFB"
                    Text { anchors.centerIn: parent; text: uploaderStarted ? "取消上传" : "启动上传"; font.pixelSize: 11; color: uploaderStarted ? "#D32F2F" : "#1565C0" }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (uploaderStarted) {
                                stopUploaderService()
                            } else {
                                uploaderStarted = false
                                startUploaderService()
                            }
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 24
                    radius: 3
                    color: "#2f7dcc"
                    Text { anchors.centerIn: parent; text: "手动输入书名"; font.pixelSize: 11; color: "#fff" }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: showKeyboard("", function(text) {
                            var url = normalizeBookInput(text)
                            if (url) loadFile(url)
                        })
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: 4
                color: "#F8F4EC"
                border.color: "#E0D8C8"
                Text {
                    anchors.centerIn: parent
                    text: "我的书架 (" + bookList.length + ")"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#333333"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: openShelf()
                }
            }

            Row {
                width: parent.width
                height: 28
                spacing: 6

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 28
                    radius: 4
                    color: "#FFF3E0"
                    border.color: "#FFCC80"
                    Text {
                        anchors.centerIn: parent
                        text: "☕ 赞赏作者"
                        font.pixelSize: 12
                        color: "#E65100"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { sponsorQrIndex = 0; showSponsor = true }
                    }
                }

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: 28
                    radius: 4
                    color: "#E8F5E9"
                    border.color: "#A5D6A7"
                    Text {
                        anchors.centerIn: parent
                        text: "QQ群 1040494353"
                        font.pixelSize: 12
                        color: "#2E7D32"
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: homeMode === "shelf"

            Column {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                Row {
                    width: parent.width
                    height: 24
                    spacing: 6

                    Rectangle {
                        width: 58
                        height: 24
                        radius: 4
                        color: "#DDDDDD"
                        Text { anchors.centerIn: parent; text: "返回"; font.pixelSize: 11; color: "#333333" }
                        MouseArea { anchors.fill: parent; onClicked: closeShelf() }
                    }

                    Text {
                        width: parent.width - 64 - 52
                        height: 24
                        text: "我的书架 (" + bookList.length + ")"
                        font.pixelSize: 14
                        font.bold: true
                        color: textColor
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        width: 52
                        height: 24
                        radius: 4
                        color: "#E3F2FD"
                        border.color: "#BBDEFB"
                        Text { anchors.centerIn: parent; text: "教程"; font.pixelSize: 11; color: "#1565C0" }
                        MouseArea { anchors.fill: parent; onClicked: openTutorial() }
                    }
                }

                ListView {
                    width: parent.width
                    height: parent.height - 28
                    clip: true
                    spacing: 3
                    model: bookList
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        width: parent.width
                        height: 24
                        radius: 3
                        color: bookMouse.pressed ? "#E0D8C8" : "#F8F4EC"
                        border.color: "#E0D8C8"

                        MouseArea {
                            id: bookMouse
                            anchors.fill: parent
                            z: 0
                            onClicked: {
                                isLoading = true
                                statusMessage = ""
                                loadFile(modelData.file)
                            }
                        }

                        Row {
                            z: 1
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 4

                            Text {
                                width: parent.width - 60
                                text: modelData.name
                                font.pixelSize: 11
                                color: "#333"
                                elide: Text.ElideMiddle
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData.progress + "%"
                                font.pixelSize: 9
                                color: "#888"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: bookList.length === 0
                        text: "暂无小说\n请将 txt 放到 /userdisk/Music/"
                        font.pixelSize: 11
                        color: textColor
                        opacity: 0.5
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    Item {
        id: readerPage
        anchors.fill: parent
        visible: currentUrl !== ""

        Text {
            id: contentText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: readerMargin
            anchors.rightMargin: readerMargin
            anchors.topMargin: readerMargin
            anchors.bottomMargin: readerMargin
            text: getPageText()
            font.pixelSize: baseFontSize
            lineHeightMode: Text.FixedHeight
            lineHeight: getTextLineHeight()
            color: textColor
            wrapMode: Text.NoWrap
            clip: true
        }

        MouseArea {
            id: pageTouch
            anchors.fill: parent
            enabled: activePanel === "" && !isLoading
            property real startX: 0
            property real startY: 0
            property bool moved: false

            onPressed: {
                startX = mouseX
                startY = mouseY
                moved = false
            }

            onPositionChanged: {
                if (Math.abs(mouseX - startX) > 15 || Math.abs(mouseY - startY) > 15) moved = true
            }

            onReleased: {
                var dx = mouseX - startX
                var dy = mouseY - startY
                var dist = Math.sqrt(dx * dx + dy * dy)

                if (moved && dist > 30) {
                    if (Math.abs(dy) > Math.abs(dx)) {
                        if (dy < 0) nextPage()
                        else prevPage()
                    } else {
                        if (dx < 0) nextPage()
                        else prevPage()
                    }
                    return
                }

                if (mouseX > width / 3 && mouseX < width * 2 / 3) openPanel("menu")
                else if (mouseX < width / 3) prevPage()
                else nextPage()
            }
        }
    }

    Rectangle {
        id: menuPanel
        visible: activePanel === "menu" && currentUrl !== ""
        anchors.fill: parent
        anchors.margins: 8
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 40

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            Row {
                width: parent.width
                height: 22
                Text {
                    width: parent.width - 28
                    text: fileName
                    font.pixelSize: 12
                    font.bold: true
                    color: textColor
                    elide: Text.ElideMiddle
                    verticalAlignment: Text.AlignVCenter
                }
                Rectangle {
                    width: 22; height: 22; radius: 11; color: "#DDDDDD"
                    Text { anchors.centerIn: parent; text: "x"; font.pixelSize: 13; color: "#333" }
                    MouseArea { anchors.fill: parent; onClicked: closePanels() }
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 27
                contentWidth: width
                contentHeight: menuContent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: menuContent
                    width: parent.width
                    spacing: 5

                    Text {
                        width: parent.width
                        text: "进度: " + getProgressPercent() + "% (" + getCurrentPage() + "/" + getTotalPages() + "页)"
                        font.pixelSize: 11
                        color: textColor
                    }

                    Rectangle {
                        width: parent.width
                        height: 12
                        radius: 6
                        color: "#CCCCCC"
                        Rectangle {
                            width: parent.width * (getProgressPercent() / 100)
                            height: parent.height
                            radius: 6
                            color: "#2f7dcc"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: jumpToPercent((mouseX / width) * 100)
                        }
                    }

                    Row {
                        spacing: 4
                        Repeater {
                            model: [{t:"小",v:13},{t:"中",v:15},{t:"大",v:18}]
                            delegate: Rectangle {
                                width: 42; height: 20; radius: 3
                                color: baseFontSize === modelData.v ? "#2f7dcc" : "#EEEEEE"
                                Text { anchors.centerIn: parent; text: modelData.t; font.pixelSize: 10; color: baseFontSize === modelData.v ? "#fff" : "#333" }
                                MouseArea { anchors.fill: parent; onClicked: setFontSize(modelData.v) }
                            }
                        }
                    }

                    Row {
                        spacing: 4
                        Repeater {
                            model: [{t:"紧凑",v:2},{t:"标准",v:4},{t:"宽松",v:6}]
                            delegate: Rectangle {
                                width: 56; height: 20; radius: 3
                                color: lineSpacing === modelData.v ? "#2f7dcc" : "#EEEEEE"
                                Text { anchors.centerIn: parent; text: modelData.t; font.pixelSize: 10; color: lineSpacing === modelData.v ? "#fff" : "#333" }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        lineSpacing = modelData.v
                                        clampCurrentLine()
                                        saveSettings()
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 3
                        Repeater {
                            model: [{n:"默认",c:"#FFFBF0"},{n:"白色",c:"#FFFFFF"},{n:"黄色",c:"#FFF8E1"},{n:"绿色",c:"#E8F5E9"},{n:"黑色",c:"#263238"},{n:"粉色",c:"#FCE4EC"},{n:"蓝色",c:"#E3F2FD"}]
                            delegate: Rectangle {
                                width: 28; height: 20; radius: 3
                                color: modelData.c
                                border.color: themeName === modelData.n ? "#2f7dcc" : "#BBBBBB"
                                border.width: themeName === modelData.n ? 2 : 1
                                Text { anchors.centerIn: parent; text: modelData.n.charAt(0); font.pixelSize: 9; color: modelData.n === "黑色" ? "#ECEFF1" : "#333" }
                                MouseArea { anchors.fill: parent; onClicked: setTheme(modelData.n) }
                            }
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 3
                        rowSpacing: 4
                        columnSpacing: 4

                        MenuButton { label: "返回书架"; w: (menuContent.width - 8) / 3; onClicked: returnToShelf() }
                        MenuButton { label: "跳转"; w: (menuContent.width - 8) / 3; onClicked: openPanel("jump") }
                        MenuButton { label: "书签"; w: (menuContent.width - 8) / 3; onClicked: openPanel("bookmarks") }
                        MenuButton { label: "添加书签"; w: (menuContent.width - 8) / 3; bg: "#E8F5E9"; fg: "#2E7D32"; onClicked: addBookmark() }
                        MenuButton {
                            label: autoScroll ? "停止翻页" : "自动翻页"
                            w: (menuContent.width - 8) / 3
                            onClicked: {
                                if (autoScroll) autoScroll = false
                                else openPanel("auto")
                            }
                        }
                        MenuButton { label: "删除记录"; w: (menuContent.width - 8) / 3; bg: "#FFD0D0"; fg: "#D32F2F"; onClicked: deleteCurrentRecord() }
                    }

                    Row {
                        width: parent.width
                        spacing: 4
                        MenuButton { label: "上一章"; w: (menuContent.width - 4) / 2; bg: "#E3F2FD"; fg: "#1565C0"; onClicked: jumpToChapter(-1) }
                        MenuButton { label: "下一章"; w: (menuContent.width - 4) / 2; bg: "#E3F2FD"; fg: "#1565C0"; onClicked: jumpToChapter(1) }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: activePanel === "jump"
        anchors.fill: parent
        anchors.margins: 10
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Row {
                width: parent.width
                height: 20
                Text { width: parent.width - 28; text: "跳转到"; font.pixelSize: 13; font.bold: true; color: textColor }
                MenuButton { label: "x"; w: 22; h: 20; onClicked: closePanels() }
            }

            Text {
                width: parent.width
                text: "第" + getCurrentPage() + "页 / 共" + getTotalPages() + "页 (" + getProgressPercent() + "%)"
                font.pixelSize: 10
                color: textColor
            }

            Row {
                spacing: 4
                Repeater {
                    model: [{t:"0%",v:0},{t:"25%",v:25},{t:"50%",v:50},{t:"75%",v:75},{t:"100%",v:100}]
                    delegate: MenuButton { label: modelData.t; w: 42; h: 21; bg: "#2f7dcc"; fg: "#fff"; onClicked: { jumpToPercent(modelData.v); closePanels() } }
                }
            }

            ListView {
                width: parent.width
                height: 44
                clip: true
                spacing: 2
                visible: chapterList.length > 0
                model: chapterList

                delegate: Rectangle {
                    width: parent.width
                    height: 20
                    radius: 2
                    color: chapterMouse.pressed ? "#E0D8C8" : "#F5F0E8"
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        font.pixelSize: 10
                        color: "#333"
                        elide: Text.ElideRight
                        width: parent.width - 8
                    }
                    MouseArea {
                        id: chapterMouse
                        anchors.fill: parent
                        onClicked: {
                            currentLine = modelData.lineIndex
                            saveProgress()
                            closePanels()
                        }
                    }
                }
            }

            Row {
                spacing: 6
                MenuButton {
                    label: "输入页数"; w: 70; h: 22
                    onClicked: {
                        activePanel = ""
                        showKeyboard(String(getCurrentPage()), function(text) {
                            var page = parseInt(text)
                            if (!isNaN(page)) jumpToPage(page)
                        })
                    }
                }
                MenuButton {
                    label: "输入百分比"; w: 78; h: 22
                    onClicked: {
                        activePanel = ""
                        showKeyboard(String(getProgressPercent()), function(text) {
                            var percent = parseInt(text)
                            if (!isNaN(percent)) jumpToPercent(percent)
                        })
                    }
                }
                MenuButton { label: "关闭"; w: 50; h: 22; onClicked: closePanels() }
            }
        }
    }

    Rectangle {
        visible: activePanel === "bookmarks"
        anchors.fill: parent
        anchors.margins: 10
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            Row {
                width: parent.width
                height: 22
                Text { width: parent.width - 28; text: "书签 (" + bookmarkList.length + ")"; font.pixelSize: 13; font.bold: true; color: textColor }
                MenuButton { label: "x"; w: 22; h: 22; onClicked: closePanels() }
            }

            Rectangle { width: parent.width; height: 1; color: "#EEEEEE" }

            ListView {
                width: parent.width
                height: parent.height - 32
                clip: true
                spacing: 4
                model: bookmarkList

                delegate: Rectangle {
                    width: parent.width
                    height: 36
                    radius: 4
                    color: bmMouse.pressed ? "#E0D8C8" : "#F5F0E8"
                    border.color: "#DDDDDD"

                    MouseArea {
                        id: bmMouse
                        anchors.fill: parent
                        z: 0
                        onClicked: {
                            currentLine = modelData.line
                            clampCurrentLine()
                            saveProgress()
                            closePanels()
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: deleteButton.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "书签 " + (index + 1) + " - 第" + (Math.floor(modelData.line / getLinesPerPage()) + 1) + "页"; font.pixelSize: 11; color: "#333" }
                        Text { width: parent.width; text: modelData.preview || "..."; font.pixelSize: 9; color: "#888"; elide: Text.ElideRight }
                    }

                    Rectangle {
                        id: deleteButton
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: 12
                        color: "#D9534F"
                        z: 2
                        Text { anchors.centerIn: parent; text: "x"; font.pixelSize: 13; color: "#fff" }
                        MouseArea {
                            anchors.fill: parent
                            z: 3
                            onClicked: deleteBookmark(modelData.id)
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: bookmarkList.length === 0
                    text: "暂无书签\n阅读时点击「添加书签」"
                    font.pixelSize: 11
                    color: textColor
                    opacity: 0.5
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        visible: activePanel === "auto"
        anchors.fill: parent
        anchors.margins: 25
        radius: 6
        color: bgColor === "#263238" ? "#37474F" : "#FFFFFF"
        border.color: "#CCCCCC"
        z: 50

        Column {
            anchors.centerIn: parent
            spacing: 9
            width: parent.width - 16

            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "自动翻页"; font.pixelSize: 14; font.bold: true; color: textColor }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "间隔: " + autoScrollSeconds + " 秒/页"; font.pixelSize: 11; color: textColor }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                MenuButton {
                    label: "输入秒数"
                    w: 86
                    h: 24
                    bg: "#E3F2FD"
                    fg: "#1565C0"
                    onClicked: {
                        activePanel = ""
                        showKeyboard(String(autoScrollSeconds), function(text) {
                            autoScrollSeconds = normalizeAutoScrollSeconds(text)
                            saveSettings()
                            openPanel("auto")
                        })
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                MenuButton { label: "开始"; w: 76; h: 26; bg: "#2f7dcc"; fg: "#fff"; onClicked: { autoScroll = true; closePanels() } }
                MenuButton { label: "取消"; w: 76; h: 26; onClicked: closePanels() }
            }
        }
    }

    Rectangle {
        visible: showTutorial
        anchors.fill: parent
        color: "#FFFBF0"
        z: 80

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            Row {
                width: parent.width
                height: 24
                spacing: 6

                Rectangle {
                    width: 58
                    height: 24
                    radius: 4
                    color: "#DDDDDD"
                    Text { anchors.centerIn: parent; text: "返回"; font.pixelSize: 11; color: "#333333" }
                    MouseArea { anchors.fill: parent; onClicked: showTutorial = false }
                }

                Text {
                    width: parent.width - 58 - 6
                    height: 24
                    text: "使用教程 (" + (tutorialLines.length > 0 ? Math.floor(tutorialLine / 8) + 1 + "/" + Math.ceil(tutorialLines.length / 8) : "1/1") + ")"
                    font.pixelSize: 12
                    font.bold: true
                    color: "#333333"
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Text {
                width: parent.width
                height: parent.height - 28
                text: {
                    var start = tutorialLine
                    var end = Math.min(start + 8, tutorialLines.length)
                    var page = []
                    for (var i = start; i < end; i++) page.push(tutorialLines[i])
                    return page.join("\n")
                }
                font.pixelSize: 12
                color: "#333333"
                lineHeight: 1.5
                wrapMode: Text.WordWrap
                clip: true
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: 28
            property real startX: 0
            property real startY: 0
            property bool moved: false

            onPressed: { startX = mouseX; startY = mouseY; moved = false }
            onPositionChanged: { if (Math.abs(mouseX - startX) > 10 || Math.abs(mouseY - startY) > 10) moved = true }
            onReleased: {
                if (moved) {
                    var dy = mouseY - startY
                    if (dy < -10 && tutorialLine + 8 < tutorialLines.length) tutorialLine += 8
                    else if (dy > 10 && tutorialLine >= 8) tutorialLine -= 8
                } else {
                    if (mouseX > width / 2 && tutorialLine + 8 < tutorialLines.length) tutorialLine += 8
                    else if (mouseX <= width / 2 && tutorialLine >= 8) tutorialLine -= 8
                }
            }
        }
    }

    Rectangle {
        visible: isLoading
        anchors.centerIn: parent
        width: 84
        height: 24
        radius: 4
        color: "#FFFFFF"
        border.color: "#DDDDDD"
        z: 100
        Text { anchors.centerIn: parent; text: "加载中..."; font.pixelSize: 11; color: "#333" }
    }

    Text {
        anchors.centerIn: parent
        visible: statusMessage !== "" && !isLoading
        text: statusMessage
        font.pixelSize: 13
        color: "#D32F2F"
        z: 100
    }

    Rectangle {
        visible: showSponsor
        anchors.fill: parent
        color: "#80000000"
        z: 110

        MouseArea {
            anchors.fill: parent
            onClicked: showSponsor = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 280
            height: 150
            radius: 10
            color: "#FFFFFF"
            border.color: "#EEEEEE"

            MouseArea { anchors.fill: parent }

            Row {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                Column {
                    width: parent.width - 100 - 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        width: parent.width
                        text: "❤ 支持一下作者"
                        font.pixelSize: 13
                        font.bold: true
                        color: "#E65100"
                    }

                    Text {
                        width: parent.width
                        text: "这款阅读器花了很长时间\n开发和打磨，如果觉得好用\n希望能请作者喝杯奶茶 ☕\n你的支持是我的动力 ❤"
                        font.pixelSize: 9
                        color: "#666666"
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                    }

                    Rectangle {
                        width: 52
                        height: 20
                        radius: 3
                        color: "#F5F5F5"
                        border.color: "#E0E0E0"
                        Text {
                            anchors.centerIn: parent
                            text: "关闭"
                            font.pixelSize: 10
                            color: "#999999"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: showSponsor = false
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Image {
                        width: 100
                        height: 100
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: sponsorQrIndex === 0 ? Qt.resolvedUrl("Thanks.PNG") : Qt.resolvedUrl("weixin.png")
                        fillMode: Image.PreserveAspectFit
                        cache: false

                        MouseArea {
                            anchors.fill: parent
                            onClicked: sponsorQrIndex = sponsorQrIndex === 0 ? 1 : 0
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: sponsorQrIndex === 0 ? "爱发电 · 点击切换微信" : "微信 · 点击切换爱发电"
                        font.pixelSize: 8
                        color: "#AAAAAA"
                    }
                }
            }
        }
    }

    YPagePopHelper {
        id: pagePopHelper
        z: 99
        property var containerItem: this
        isShowing: typeof qmlGlobal !== "undefined" ? qmlGlobal.inputPageShowing : false
    }
}
