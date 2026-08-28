@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ============================================================================
rem Generate-Directory-Network.bat
rem Version: 2.7.1-network
rem Entry: run directly from cmd.exe. PowerShell is not used.
rem Runtime: Windows Script Host (cscript.exe), built into Windows.
rem Markdown repair: validate title/tags/abbrlink/date; categories is optional.
rem Add no-referrer only when a remote Markdown/HTML image is referenced.
rem Article write-back preserves existing whitespace, blank lines, newline style, and BOM state.
rem Console output includes an in-place Markdown scan progress bar.

rem 当前 cmd 目录
@REM Generate-Directory-Network.bat

@REM rem 相对路径，以当前 cmd 目录为基准
@REM Generate-Directory-Network.bat ..\canopen

@REM rem 绝对路径，包含空格时必须加双引号
@REM Generate-Directory-Network.bat "D:\Study Notes\CANopen"

@REM rem 路径和选项组合
@REM Generate-Directory-Network.bat "D:\Study Notes\CANopen" --offline
rem ============================================================================

chcp 65001 >nul

set "GEN_DIR_VERSION=2.7.1-network"
set "HEXO_BASE=https://wdfk-prog.space/posts/"
set "CSDN_USER=qq_39665253"
set "CSDN_API=https://blog.csdn.net/community/home-api/v1/get-business-list"
set "CSDN_PAGE_SIZE=100"
set "CSDN_MAX_PAGES=20"

set "JS_FILE=%TEMP%\Generate-Directory-%RANDOM%-%RANDOM%.js"
set "PAYLOAD_LINE="

for /f "tokens=1 delims=:" %%N in ('findstr /n /b /c:"//__JSCRIPT_PAYLOAD__" "%~f0"') do set "PAYLOAD_LINE=%%N"

if not defined PAYLOAD_LINE (
    echo [ERROR] Embedded JScript payload was not found.
    exit /b 2
)

more +%PAYLOAD_LINE% "%~f0" > "%JS_FILE%"
if errorlevel 1 (
    echo [ERROR] Failed to extract the embedded JScript payload.
    del /q "%JS_FILE%" >nul 2>nul
    exit /b 3
)

cscript //nologo //E:JScript "%JS_FILE%" "%CD%" "%HEXO_BASE%" "%CSDN_USER%" "%CSDN_API%" "%CSDN_PAGE_SIZE%" "%CSDN_MAX_PAGES%" "%GEN_DIR_VERSION%" %*
set "RC=%ERRORLEVEL%"

del /q "%JS_FILE%" >nul 2>nul
exit /b %RC%

//__JSCRIPT_PAYLOAD__
/**
 * @brief JScript 主入口：解析参数、扫描目录、检查 Markdown 并生成目录文件。
 * @return 无。完成后通过 WScript.Quit 返回进程退出码。
 */
(function () {
    var fso = new ActiveXObject("Scripting.FileSystemObject");
    var shell = new ActiveXObject("WScript.Shell");
    var args = WScript.Arguments;

    if (args.length < 7) {
        WScript.Echo("[ERROR] Invalid launcher arguments.");
        WScript.Quit(10);
    }

    var launchCwd = fso.GetAbsolutePathName(args.Item(0));
    var hexoBase = ensureTrailingSlash(args.Item(1));
    var csdnUser = args.Item(2);
    var csdnApi = args.Item(3);
    var csdnPageSize = parsePositiveInt(args.Item(4), 100);
    var csdnMaxPages = parsePositiveInt(args.Item(5), 20);
    var version = args.Item(6);

    var options = {
        offline: false,
        noCsdn: false,
        maxDepth: 10,
        outputName: ""
    };

    var targetArgument = "";
    var i;
    for (i = 7; i < args.length; i++) {
        var arg = String(args.Item(i));
        if (arg === "--offline") {
            options.offline = true;
        } else if (arg === "--no-csdn") {
            options.noCsdn = true;
        } else if (arg.indexOf("--max-depth=") === 0) {
            options.maxDepth = parsePositiveInt(arg.substring(12), 10);
        } else if (arg.indexOf("--output=") === 0) {
            options.outputName = stripOuterQuotes(arg.substring(9));
        } else if (arg === "--help" || arg === "-h" || arg === "/?") {
            printHelp();
            WScript.Quit(0);
        } else if (arg.indexOf("--") === 0) {
            WScript.Echo("[ERROR] Unknown option: " + arg);
            WScript.Quit(12);
        } else if (!targetArgument) {
            targetArgument = stripOuterQuotes(arg);
        } else {
            WScript.Echo("[ERROR] Only one target directory can be specified.");
            WScript.Quit(13);
        }
    }

    var rootPath = resolveTargetPath(launchCwd, targetArgument);

    if (!fso.FolderExists(rootPath)) {
        WScript.Echo("[ERROR] Root directory does not exist: " + rootPath);
        WScript.Quit(11);
    }

    var rootFolder = fso.GetFolder(rootPath);
    var folderName = rootFolder.Name;
    if (!folderName) {
        folderName = "Study";
    }

    var suffix = "\u5b66\u4e60\u7b14\u8bb0\u7cfb\u5217";
    var documentTitle = folderName + suffix;
    var outputName = options.outputName || (documentTitle + ".md");
    outputName = sanitizeFileName(outputName);
    if (!/\.md$/i.test(outputName)) {
        outputName += ".md";
    }

    var outputPath = fso.BuildPath(rootPath, outputName);
    var cachePath = "";

    var csdnArticles = [];
    var csdnSource = "disabled";
    if (!options.noCsdn) {
        try {
            cachePath = getCsdnCachePath(csdnUser);
        } catch (cachePathError) {
            WScript.Echo("[WARN] CSDN cache path unavailable: " + safeError(cachePathError));
        }

        if (!options.offline) {
            try {
                csdnArticles = fetchCsdnArticles(csdnApi, csdnUser, csdnPageSize, csdnMaxPages);
                if (csdnArticles.length > 0) {
                    csdnSource = "network";
                    if (cachePath) {
                        try {
                            saveCsdnCache(cachePath, csdnArticles);
                        } catch (cacheWriteError) {
                            WScript.Echo("[WARN] CSDN cache write failed: " + safeError(cacheWriteError));
                        }
                    }
                }
            } catch (fetchError) {
                WScript.Echo("[WARN] CSDN online list failed: " + safeError(fetchError));
            }
        }

        if (csdnArticles.length === 0 && cachePath && fso.FileExists(cachePath)) {
            try {
                csdnArticles = loadCsdnCache(cachePath);
                csdnSource = "cache";
            } catch (cacheError) {
                WScript.Echo("[WARN] CSDN cache failed: " + safeError(cacheError));
            }
        }

        if (csdnArticles.length === 0) {
            csdnSource = "unavailable";
        }
    }

    var lines = [];
    lines.push("# " + documentTitle);
    lines.push("");

    // 记录 Markdown 检查和修复数量，便于核对实际执行范围。
    var markdownStats = {
        scanned: 0,
        empty: 0,
        frontMatterMissing: 0,
        frontMatterIncomplete: 0,
        remoteImage: 0,
        metaAdded: 0,
        failed: 0
    };

    // 在正式处理前先统计 Markdown 总数，使进度条能够显示准确百分比。
    var markdownTotal = countMarkdownFiles(rootFolder, 0, outputPath, options.maxDepth);
    var progress = createProgressState(markdownTotal);
    renderProgress(progress);

    var rootResult = buildDirectory(rootFolder, "", 0, "", outputPath, options.maxDepth, hexoBase, csdnUser, csdnArticles, options.noCsdn, markdownStats, progress);
    appendArray(lines, rootResult.lines);

    // 目录扫描完成后结束当前进度行，再输出固定格式的汇总信息。
    finishProgress(progress);
    writeUtf8(outputPath, lines.join("\r\n") + "\r\n");

    WScript.Echo("[OK] Version: " + version);
    WScript.Echo("[OK] Output: " + outputPath);
    WScript.Echo("[OK] CSDN source: " + csdnSource + ", articles: " + csdnArticles.length);
    if (cachePath) {
        WScript.Echo("[OK] CSDN cache: " + cachePath);
    }
    WScript.Echo("[OK] Markdown scanned: " + markdownStats.scanned);
    WScript.Echo("[OK] Empty Markdown skipped: " + markdownStats.empty);
    WScript.Echo("[OK] Front Matter missing: " + markdownStats.frontMatterMissing);
    WScript.Echo("[OK] Front Matter incomplete: " + markdownStats.frontMatterIncomplete);
    WScript.Echo("[OK] Remote image articles: " + markdownStats.remoteImage);
    WScript.Echo("[OK] Referrer meta added: " + markdownStats.metaAdded);
    WScript.Echo("[OK] Markdown update failed: " + markdownStats.failed);
    WScript.Quit(0);

    /**
     * @brief 输出命令行帮助信息。
     * @return 无。
     */
    function printHelp() {
        WScript.Echo("Generate-Directory-Network.bat [target-folder] [options]");
        WScript.Echo("");
        WScript.Echo("Target folder:");
        WScript.Echo("  Omitted           Use the current cmd.exe directory.");
        WScript.Echo("  Relative path     Resolve relative to the current cmd.exe directory.");
        WScript.Echo("  Absolute path     Use the specified directory directly.");
        WScript.Echo("");
        WScript.Echo("Options:");
        WScript.Echo("  --offline         Do not access CSDN; use the local cache only.");
        WScript.Echo("  --no-csdn         Do not emit CSDN links.");
        WScript.Echo("  --max-depth=N     Set recursive scan depth. Default: 10.");
        WScript.Echo("  --output=NAME.md  Override the generated Markdown filename.");
        WScript.Echo("");
        WScript.Echo("Examples:");
        WScript.Echo("  Generate-Directory-Network.bat");
        WScript.Echo("  Generate-Directory-Network.bat ..\\canopen");
        WScript.Echo('  Generate-Directory-Network.bat "D:\\Notes\\CANopen"');
    }

    /**
     * @brief 解析用户指定的目标目录。
     * @param basePath 启动时的当前目录。
     * @param targetPath 用户输入的目标路径。
     * @return 规范化后的绝对路径。
     */
    function resolveTargetPath(basePath, targetPath) {
        var value = String(targetPath || "").replace(/^\s+|\s+$/g, "");
        if (!value || value === ".") {
            return fso.GetAbsolutePathName(basePath);
        }
        if (/^[A-Za-z]:[\\\/]/.test(value) || /^[\\\/]{1,2}/.test(value)) {
            return fso.GetAbsolutePathName(value);
        }
        return fso.GetAbsolutePathName(fso.BuildPath(basePath, value));
    }

    /**
     * @brief 构造当前用户的 CSDN 缓存文件路径。
     * @param username CSDN 用户名。
     * @return 缓存文件绝对路径。
     */
    function getCsdnCachePath(username) {
        var basePath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%");
        if (!basePath || basePath === "%LOCALAPPDATA%") {
            basePath = shell.ExpandEnvironmentStrings("%TEMP%");
        }
        if (!basePath || basePath === "%TEMP%") {
            throw new Error("LOCALAPPDATA and TEMP are unavailable; cannot create CSDN cache.");
        }

        var cacheFolder = fso.BuildPath(basePath, "Generate-Directory-Network");
        if (!fso.FolderExists(cacheFolder)) {
            fso.CreateFolder(cacheFolder);
        }

        var safeUser = String(username || "default").replace(/[^A-Za-z0-9_.-]/g, "_");
        return fso.BuildPath(cacheFolder, "CSDN-" + safeUser + ".tsv");
    }

    /**
     * @brief 递归扫描目录并生成 Markdown 目录项。
     * @param folder 当前目录对象。
     * @param relativeDir 相对根目录的路径。
     * @param depth 当前递归深度。
     * @param numberPrefix 当前目录编号前缀。
     * @param generatedOutputPath 生成目录文件的绝对路径。
     * @param maxDepth 允许的最大递归深度。
     * @param siteBase 个人博客文章基础地址。
     * @param blogUser CSDN 用户名。
     * @param blogArticles 已获取的 CSDN 文章数组。
     * @param disableCsdn 禁用 CSDN 链接时为 true。
     * @param stats Markdown 扫描统计对象。
     * @param progress Markdown 扫描进度状态对象。
     * @return 包含目录行和 Markdown 存在状态的对象。
     */
    function buildDirectory(folder, relativeDir, depth, numberPrefix, generatedOutputPath, maxDepth, siteBase, blogUser, blogArticles, disableCsdn, stats, progress) {
        var result = { lines: [], hasMarkdown: false };
        if (depth > maxDepth) {
            return result;
        }

        var childFolders = collectionToArray(folder.SubFolders);
        var childFiles = collectionToArray(folder.Files);
        childFolders.sort(compareByName);
        childFiles.sort(compareByName);

        var counter = 1;
        var j;

        for (j = 0; j < childFolders.length; j++) {
            var childFolder = childFolders[j];
            if (String(childFolder.Name).toLowerCase() === ".vscode") {
                continue;
            }

            var childRelative = relativeDir ? (relativeDir + "/" + childFolder.Name) : childFolder.Name;
            var childNumber = numberPrefix ? (numberPrefix + counter + ".") : (counter + ".");
            var childResult = buildDirectory(childFolder, childRelative, depth + 1, childNumber, generatedOutputPath, maxDepth, siteBase, blogUser, blogArticles, disableCsdn, stats, progress);

            if (childResult.hasMarkdown) {
                result.hasMarkdown = true;
                result.lines.push(repeat("  ", depth) + "- " + childNumber + " [" + escapeMarkdownLabel(childFolder.Name) + "](<./" + encodeRelativePath(childRelative) + "/>)");
                appendArray(result.lines, childResult.lines);
                counter++;
            }
        }

        for (j = 0; j < childFiles.length; j++) {
            var file = childFiles[j];
            if (!/\.md$/i.test(file.Name)) {
                continue;
            }
            if (samePath(file.Path, generatedOutputPath)) {
                continue;
            }

            var fileRelative = relativeDir ? (relativeDir + "/" + file.Name) : file.Name;

            // 扫描 Markdown 文件，检查 Front Matter 和 referrer meta。
            // 缺少 Front Matter 时只提示，不自动修改 Front Matter。
            inspectMarkdownArticle(file.Path, stats, progress);
            advanceProgress(progress);

            var article = readArticleMetadata(file.Path);
            var displayTitle = article.title || removeExtension(file.Name);
            var currentNumber = numberPrefix ? (numberPrefix + counter + ".") : (counter + ".");
            var entry = repeat("  ", depth) + "- [" + currentNumber + " " + escapeMarkdownLabel(displayTitle) + "](<./" + encodeRelativePath(fileRelative) + ">)";

            if (article.abbrlink) {
                entry += " ([\u4e2a\u4eba\u535a\u5ba2\u94fe\u63a5](" + siteBase + encodeURIComponent(article.abbrlink) + "/))";
            }

            if (!disableCsdn) {
                var matched = findBestCsdnMatch(displayTitle, blogArticles);
                if (matched) {
                    entry += " ([CSDN\u94fe\u63a5](" + matched.url + "))";
                }
            }

            result.lines.push(entry);
            result.hasMarkdown = true;
            counter++;
        }

        return result;
    }


    /**
     * @brief 递归统计将被处理的 Markdown 文件数量。
     * @param folder 当前目录对象。
     * @param depth 当前递归深度。
     * @param generatedOutputPath 生成目录文件的绝对路径。
     * @param maxDepth 允许的最大递归深度。
     * @return 排除生成文件和 .vscode 目录后的 Markdown 文件总数。
     */
    function countMarkdownFiles(folder, depth, generatedOutputPath, maxDepth) {
        if (depth > maxDepth) {
            return 0;
        }

        var total = 0;
        var childFolders = collectionToArray(folder.SubFolders);
        var childFiles = collectionToArray(folder.Files);
        var i;

        for (i = 0; i < childFiles.length; i++) {
            if (/\.md$/i.test(childFiles[i].Name) && !samePath(childFiles[i].Path, generatedOutputPath)) {
                total++;
            }
        }

        for (i = 0; i < childFolders.length; i++) {
            if (String(childFolders[i].Name).toLowerCase() === ".vscode") {
                continue;
            }
            total += countMarkdownFiles(childFolders[i], depth + 1, generatedOutputPath, maxDepth);
        }

        return total;
    }

    /**
     * @brief 创建 Markdown 扫描进度状态对象。
     * @param total 需要处理的 Markdown 文件总数。
     * @return 可供进度输出函数共享的状态对象。
     */
    function createProgressState(total) {
        return {
            total: total > 0 ? total : 0,
            current: 0,
            width: 30,
            visible: false,
            lastLength: 0
        };
    }

    /**
     * @brief 在当前控制台行原地绘制 Markdown 扫描进度条。
     * @param progress Markdown 扫描进度状态对象。
     * @return 无。
     */
    function renderProgress(progress) {
        if (!progress) {
            return;
        }

        var percent = progress.total > 0 ? Math.floor(progress.current * 100 / progress.total) : 100;
        var filled = progress.total > 0 ? Math.floor(progress.current * progress.width / progress.total) : progress.width;
        if (filled < 0) {
            filled = 0;
        }
        if (filled > progress.width) {
            filled = progress.width;
        }

        var line = "[SCAN] [" + repeat("#", filled) + repeat("-", progress.width - filled) + "] " + percent + "% (" + progress.current + "/" + progress.total + ")";
        var padding = progress.lastLength > line.length ? repeat(" ", progress.lastLength - line.length) : "";

        WScript.StdOut.Write("\r" + line + padding);
        progress.visible = true;
        progress.lastLength = line.length;
    }

    /**
     * @brief 清除当前控制台中的进度条行，为警告或修复信息让出独立行。
     * @param progress Markdown 扫描进度状态对象。
     * @return 无。
     */
    function clearProgress(progress) {
        if (!progress || !progress.visible) {
            return;
        }

        WScript.StdOut.Write("\r" + repeat(" ", progress.lastLength) + "\r");
        progress.visible = false;
    }

    /**
     * @brief 输出不会与进度条重叠的状态消息，并恢复当前进度显示。
     * @param progress Markdown 扫描进度状态对象。
     * @param message 待输出的警告、修复或状态文本。
     * @return 无。
     */
    function writeProgressMessage(progress, message) {
        clearProgress(progress);
        WScript.Echo(message);
        renderProgress(progress);
    }

    /**
     * @brief 将已处理 Markdown 数量增加一并刷新进度条。
     * @param progress Markdown 扫描进度状态对象。
     * @return 无。
     */
    function advanceProgress(progress) {
        if (!progress) {
            return;
        }

        if (progress.current < progress.total) {
            progress.current++;
        }
        renderProgress(progress);
    }

    /**
     * @brief 完成进度显示并换行，避免后续汇总信息覆盖进度条。
     * @param progress Markdown 扫描进度状态对象。
     * @return 无。
     */
    function finishProgress(progress) {
        if (!progress) {
            return;
        }

        progress.current = progress.total;
        renderProgress(progress);
        WScript.StdOut.Write("\r\n");
        progress.visible = false;
    }


    /**
     * @brief 检查单个 Markdown 文件的 Front Matter，并按需补充 referrer meta。
     * @param filePath Markdown 文件的绝对路径。
     * @param stats Markdown 扫描统计对象。
     * @param progress Markdown 扫描进度状态对象。
     * @return 无。读取或写入失败时输出警告并继续扫描其他文件。
     */
    function inspectMarkdownArticle(filePath, stats, progress) {
        stats.scanned++;
        var fileInfo;
        try {
            fileInfo = readUtf8FileInfo(filePath);
        } catch (readError) {
            stats.failed++;
            writeProgressMessage(progress, "[WARN] Markdown read failed: " + filePath + " " + safeError(readError));
            return;
        }

        var text = fileInfo.text;

        // 空文件或纯空白文件不提示、不补充，也不执行写回。
        if (!hasNonWhitespace(text)) {
            stats.empty++;
            return;
        }

        var frontMatter = analyzeFrontMatter(text);
        if (!frontMatter.exists) {
            stats.frontMatterMissing++;
            writeProgressMessage(progress, "[WARN] Front Matter missing: " + filePath);
        } else if (frontMatter.missing.length > 0) {
            stats.frontMatterIncomplete++;
            writeProgressMessage(progress, "[WARN] Front Matter incomplete: " + filePath + " missing " + frontMatter.missing.join(", "));
        }

        // no-referrer 仅用于存在远程引用图片的文章；没有远程图片时不修改文件。
        if (!containsRemoteImageReference(text)) {
            return;
        }
        stats.remoteImage++;

        if (containsNoReferrerMeta(text)) {
            return;
        }

        var newline = detectPreferredNewline(text);
        var updated = insertNoReferrerMeta(text, frontMatter, newline);
        if (updated === text) {
            return;
        }

        try {
            // 写回时保留原文件是否带 UTF-8 BOM；正文只做一次定点插入，不重排空格或空行。
            writeUtf8PreservingBom(filePath, updated, fileInfo.hasBom);
            stats.metaAdded++;
            writeProgressMessage(progress, "[FIX] Referrer meta added: " + filePath);
        } catch (writeError) {
            stats.failed++;
            writeProgressMessage(progress, "[WARN] Markdown write failed: " + filePath + " " + safeError(writeError));
        }
    }

    /**
     * @brief 分析文件开头的 YAML Front Matter，并检查必需字段是否存在且非空；categories 为可选字段。
     * @param text Markdown 原始文本，不包含 UTF-8 BOM 字符。
     * @return Front Matter 分析结果，包含边界、缺失字段和逐行位置信息。
     */
    function analyzeFrontMatter(text) {
        var lines = getLineRecords(text);
        var result = {
            exists: false,
            endLine: -1,
            endOffset: -1,
            missing: [],
            lines: lines
        };

        if (lines.length === 0 || !/^[ \t]*---[ \t]*$/.test(lines[0].content)) {
            return result;
        }

        var endLine = -1;
        var i;
        for (i = 1; i < lines.length; i++) {
            if (/^[ \t]*(---|\.\.\.)[ \t]*$/.test(lines[i].content)) {
                endLine = i;
                break;
            }
        }

        // 没有结束标记时按缺少 Front Matter 处理，避免将正文误判为 YAML。
        if (endLine < 0) {
            return result;
        }

        result.exists = true;
        result.endLine = endLine;
        result.endOffset = lines[endLine].end;

        var required = ["title", "tags", "abbrlink", "date"];
        var fields = {
            title: false,
            tags: false,
            abbrlink: false,
            date: false
        };

        for (i = 1; i < endLine; i++) {
            var fieldMatch = /^[ \t]*([A-Za-z0-9_-]+)[ \t]*:[ \t]*(.*)$/.exec(lines[i].content);
            if (!fieldMatch) {
                continue;
            }

            var key = fieldMatch[1].toLowerCase();
            if (!fields.hasOwnProperty(key)) {
                continue;
            }

            if (hasYamlFieldValue(lines, i, endLine, key, fieldMatch[2])) {
                fields[key] = true;
            }
        }

        for (i = 0; i < required.length; i++) {
            if (!fields[required[i]]) {
                result.missing.push(required[i]);
            }
        }

        return result;
    }

    /**
     * @brief 判断 YAML 字段是否具有有效内联值或缩进列表值。
     * @param lines 包含原始行内容和字符偏移的行记录数组。
     * @param fieldLine 字段声明所在的行号。
     * @param frontMatterEnd Front Matter 结束行号。
     * @param key 字段名称。
     * @param inlineValue 冒号后的原始内联值。
     * @return 字段存在有效值时返回 true，否则返回 false。
     */
    function hasYamlFieldValue(lines, fieldLine, frontMatterEnd, key, inlineValue) {
        var value = trimHorizontal(inlineValue);
        var isEmptySequence = /^\[[ \t]*\](?:[ \t]+#.*)?$/.test(value);

        // tags: [] 表示显式配置为空标签，是合法配置，不应输出 Front Matter 警告。
        if (key === "tags" && isEmptySequence) {
            return true;
        }

        // categories 为可选字段，不参与完整性检查；其他必需字段仍要求有效值。
        if (value && value.charAt(0) !== "#" && value !== "''" && value !== '""' && !isEmptySequence) {
            return true;
        }

        // 只有 tags 支持通过后续缩进列表项提供值。
        if (key !== "tags") {
            return false;
        }

        var i;
        for (i = fieldLine + 1; i < frontMatterEnd; i++) {
            var line = lines[i].content;
            if (/^[ \t]*$/.test(line)) {
                continue;
            }
            if (/^[ \t]+-[ \t]+\S/.test(line)) {
                return true;
            }
            if (/^[^ \t]/.test(line)) {
                break;
            }
        }
        return false;
    }

    /**
     * @brief 检查文档是否引用了需要 no-referrer 策略的远程图片。
     * @param text Markdown 原始文本。
     * @return 存在 http 或 https Markdown/HTML 远程图片引用时返回 true。
     */
    function containsRemoteImageReference(text) {
        // 识别内联 Markdown 图片，例如：![描述](https://example.com/a.png)。
        if (/!\[[^\]\r\n]*\]\([ \t]*(?:<[ \t]*)?https?:\/\/[^\s)>]+(?:[ \t]+["'][^"']*["'])?[ \t]*>?[ \t]*\)/i.test(text)) {
            return true;
        }

        // 识别 HTML 图片标签，例如：<img src="https://example.com/a.png">。
        if (/<img\b[^>]*\bsrc[ \t]*=[ \t]*["'][ \t]*https?:\/\/[^"']+["'][^>]*>/i.test(text)) {
            return true;
        }

        // 识别引用式 Markdown 图片，并核对同名引用定义是否指向远程地址。
        var usage = /!\[[^\]\r\n]*\]\[([^\]\r\n]+)\]/ig;
        var match;
        while ((match = usage.exec(text)) !== null) {
            var referenceName = trimHorizontal(match[1]);
            if (!referenceName) {
                continue;
            }
            var definition = new RegExp("^[ \\t]*\\[" + escapeRegExp(referenceName) + "\\][ \\t]*:[ \\t]*<?https?:\\/\\/", "im");
            if (definition.test(text)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @brief 检查文档是否已经包含目标 no-referrer meta 标签。
     * @param text Markdown 原始文本。
     * @return 已存在等价标签时返回 true，否则返回 false。
     */
    function containsNoReferrerMeta(text) {
        var metaPattern = /<meta\b[^>]*>/ig;
        var match;
        while ((match = metaPattern.exec(text)) !== null) {
            var tag = match[0];
            var hasName = /\bname[ \t]*=[ \t]*["']referrer["']/i.test(tag);
            var hasContent = /\bcontent[ \t]*=[ \t]*["']no-referrer["']/i.test(tag);
            if (hasName && hasContent) {
                return true;
            }
        }
        return false;
    }

    /**
     * @brief 在确定位置插入 no-referrer meta，保持原有空格、空行和换行符不变。
     * @param text Markdown 原始文本。
     * @param frontMatter Front Matter 分析结果。
     * @param newline 新插入内容使用的换行符。
     * @return 仅增加 meta 文本后的 Markdown；原有字符不删除、不重排。
     */
    function insertNoReferrerMeta(text, frontMatter, newline) {
        var meta = '<meta name="referrer" content="no-referrer" />';
        var lines = frontMatter.lines || getLineRecords(text);

        if (frontMatter.exists && frontMatter.endOffset >= 0) {
            var frontMatterOffset = frontMatter.endOffset;
            var remaining = text.substring(frontMatterOffset);
            var hasFollowingBlankLine = /^[ \t]*(?:\r\n|\r|\n)/.test(remaining);
            var frontMatterInsertion = newline + meta + newline;

            // 原文没有空行时补充一个空行；原文已有空行时原样保留，不删除也不合并。
            if (!hasFollowingBlankLine) {
                frontMatterInsertion += newline;
            }

            return text.substring(0, frontMatterOffset) + frontMatterInsertion + text.substring(frontMatterOffset);
        }

        var headingIndex = findFirstLevelOneHeading(lines);
        if (headingIndex >= 0) {
            var insertionLine = headingIndex;

            // 将插入点移动到标题前连续空白行的起点，但不删除这些空白行。
            while (insertionLine > 0 && /^[ \t]*$/.test(lines[insertionLine - 1].content)) {
                insertionLine--;
            }

            var headingOffset = lines[insertionLine].start;
            var headingInsertion = meta + newline;
            if (insertionLine === headingIndex) {
                headingInsertion += newline;
            }

            return text.substring(0, headingOffset) + headingInsertion + text.substring(headingOffset);
        }

        return meta + newline + newline + text;
    }

    /**
     * @brief 查找第一个 ATX 一级标题所在的行号。
     * @param lines Markdown 行记录数组。
     * @return 找到时返回行号，否则返回 -1。
     */
    function findFirstLevelOneHeading(lines) {
        var i;
        for (i = 0; i < lines.length; i++) {
            if (/^[ \t]*#[ \t]+\S/.test(lines[i].content)) {
                return i;
            }
        }
        return -1;
    }

    /**
     * @brief 将文本解析为保留原始字符偏移和行结束符的行记录。
     * @param text 待解析文本。
     * @return 行记录数组；每项包含 content、start、contentEnd、end 和 newline。
     */
    function getLineRecords(text) {
        var lines = [];
        var position = 0;
        var length = text.length;

        while (position < length) {
            var start = position;
            var contentEnd = position;
            while (contentEnd < length && text.charAt(contentEnd) !== "\r" && text.charAt(contentEnd) !== "\n") {
                contentEnd++;
            }

            var lineEnd = contentEnd;
            var lineBreak = "";
            if (lineEnd < length) {
                if (text.charAt(lineEnd) === "\r" && lineEnd + 1 < length && text.charAt(lineEnd + 1) === "\n") {
                    lineBreak = "\r\n";
                    lineEnd += 2;
                } else {
                    lineBreak = text.charAt(lineEnd);
                    lineEnd++;
                }
            }

            lines.push({
                content: text.substring(start, contentEnd),
                start: start,
                contentEnd: contentEnd,
                end: lineEnd,
                newline: lineBreak
            });
            position = lineEnd;
        }

        return lines;
    }

    /**
     * @brief 从文本中选择新增内容使用的主要换行符。
     * @param text Markdown 原始文本。
     * @return 首个已存在的换行符；无换行符时返回 CRLF。
     */
    function detectPreferredNewline(text) {
        var match = /\r\n|\r|\n/.exec(text);
        return match ? match[0] : "\r\n";
    }

    /**
     * @brief 判断文本是否至少包含一个非空白字符。
     * @param text 待检查文本。
     * @return 存在非空白字符时返回 true，否则返回 false。
     */
    function hasNonWhitespace(text) {
        return /\S/.test(String(text || ""));
    }

    /**
     * @brief 去除字符串两端的水平空白，仅用于解析判断，不修改原文件内容。
     * @param value 待处理值。
     * @return 去除首尾空格和制表符后的字符串。
     */
    function trimHorizontal(value) {
        return String(value || "").replace(/^[ \t]+|[ \t]+$/g, "");
    }

    /**
     * @brief 转义动态正则表达式中的特殊字符。
     * @param value 待转义文本。
     * @return 可安全拼接到正则表达式中的文本。
     */
    function escapeRegExp(value) {
        return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }

    /**
     * @brief 读取文章标题和 abbrlink 元数据。
     * @param filePath 文件路径。
     * @return 包含 title 和 abbrlink 的对象。
     */
    function readArticleMetadata(filePath) {
        var text = "";
        try {
            text = readUtf8(filePath);
        } catch (readError) {
            return { title: removeExtension(fso.GetFileName(filePath)), abbrlink: "" };
        }

        text = text.replace(/^\uFEFF/, "");
        var lines = text.split(/\r\n|\n|\r/);
        var title = "";
        var abbrlink = "";
        var frontMatterEnd = -1;

        if (lines.length > 0 && /^\s*---\s*$/.test(lines[0])) {
            var k;
            for (k = 1; k < lines.length; k++) {
                if (/^\s*(---|\.\.\.)\s*$/.test(lines[k])) {
                    frontMatterEnd = k;
                    break;
                }

                var titleMatch = /^\s*title\s*:\s*(.*?)\s*$/i.exec(lines[k]);
                if (titleMatch && !title) {
                    title = cleanYamlScalar(titleMatch[1]);
                }

                var abbrMatch = /^\s*abbrlink\s*:\s*(.*?)\s*$/i.exec(lines[k]);
                if (abbrMatch && !abbrlink) {
                    abbrlink = cleanYamlScalar(abbrMatch[1]).replace(/\s+#.*$/, "");
                    if (!/^[A-Za-z0-9_-]+$/.test(abbrlink)) {
                        abbrlink = "";
                    }
                }
            }
        }

        if (!title) {
            var start = frontMatterEnd >= 0 ? frontMatterEnd + 1 : 0;
            for (var m = start; m < lines.length; m++) {
                var heading = /^\s*#\s+(.+?)\s*#*\s*$/.exec(lines[m]);
                if (heading) {
                    title = heading[1];
                    break;
                }
            }
        }

        title = cleanDisplayTitle(title);
        if (!title) {
            title = removeExtension(fso.GetFileName(filePath));
        }

        return { title: title, abbrlink: abbrlink };
    }

    /**
     * @brief 分页获取指定用户的 CSDN 文章列表。
     * @param apiUrl CSDN API 地址。
     * @param username CSDN 用户名。
     * @param pageSize 每页文章数量。
     * @param maxPages 最大请求页数。
     * @return 文章对象数组。
     */
    function fetchCsdnArticles(apiUrl, username, pageSize, maxPages) {
        var articles = [];
        var seen = {};
        var total = -1;

        for (var page = 1; page <= maxPages; page++) {
            var url = apiUrl +
                "?page=" + page +
                "&size=" + pageSize +
                "&businessType=blog" +
                "&orderby=" +
                "&noMore=false" +
                "&year=" +
                "&month=" +
                "&username=" + encodeURIComponent(username);

            var body = httpGetUtf8(url);
            var response;
            try {
                response = eval("(" + body + ")");
            } catch (jsonError) {
                throw new Error("CSDN returned invalid JSON on page " + page);
            }

            if (!response || !response.data || !response.data.list) {
                throw new Error("CSDN response schema changed on page " + page);
            }

            if (typeof response.data.total !== "undefined") {
                total = parseInt(response.data.total, 10);
            }

            var list = response.data.list;
            if (!list || list.length === 0) {
                break;
            }

            var addedThisPage = 0;
            for (var n = 0; n < list.length; n++) {
                var item = list[n];
                var title = item && item.title ? String(item.title) : "";
                var articleUrl = item && item.url ? String(item.url) : "";
                if (!title || !isAllowedCsdnArticleUrl(articleUrl)) {
                    continue;
                }
                if (!seen[articleUrl]) {
                    seen[articleUrl] = true;
                    articles.push({ title: title, url: articleUrl });
                    addedThisPage++;
                }
            }

            if (total >= 0 && articles.length >= total) {
                break;
            }
            if (list.length < pageSize || addedThisPage === 0) {
                break;
            }
        }

        return articles;
    }

    /**
     * @brief 执行同步 HTTP GET 请求并按 UTF-8 解码响应。
     * @param url 待请求或验证的 URL。
     * @return 响应正文文本。
     */
    function httpGetUtf8(url) {
        var request = new ActiveXObject("WinHttp.WinHttpRequest.5.1");
        request.SetTimeouts(10000, 10000, 20000, 20000);
        request.Open("GET", url, false);
        request.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Generate-Directory/2.7.1");
        request.SetRequestHeader("Accept", "application/json,text/plain,*/*");
        request.SetRequestHeader("Referer", "https://blog.csdn.net/");
        request.Send();

        if (request.Status < 200 || request.Status >= 300) {
            throw new Error("HTTP " + request.Status + " for " + url);
        }

        var stream = new ActiveXObject("ADODB.Stream");
        stream.Type = 1;
        stream.Open();
        stream.Write(request.ResponseBody);
        stream.Position = 0;
        stream.Type = 2;
        stream.Charset = "utf-8";
        var text = stream.ReadText();
        stream.Close();
        return text;
    }

    /**
     * @brief 为本地文章标题查找最佳 CSDN 文章匹配。
     * @param localTitle 本地文章标题。
     * @param articles 文章对象数组。
     * @return 匹配文章对象；没有可靠匹配时返回 null。
     */
    function findBestCsdnMatch(localTitle, articles) {
        if (!articles || articles.length === 0) {
            return null;
        }

        var target = normalizeTitle(localTitle);
        if (!target) {
            return null;
        }

        var exact = null;
        var best = null;
        var bestScore = 0;

        for (var p = 0; p < articles.length; p++) {
            var candidate = articles[p];
            var candidateTitle = normalizeTitle(candidate.title);
            if (!candidateTitle) {
                continue;
            }

            if (candidateTitle === target) {
                exact = candidate;
                break;
            }

            var score = titleSimilarity(target, candidateTitle);
            if (score > bestScore) {
                bestScore = score;
                best = candidate;
            }
        }

        if (exact) {
            return exact;
        }
        return bestScore >= 0.86 ? best : null;
    }

    /**
     * @brief 计算两个规范化标题的相似度。
     * @param a 第一个比较值。
     * @param b 第二个比较值。
     * @return 范围为 0 到 1 的相似度。
     */
    function titleSimilarity(a, b) {
        if (a === b) {
            return 1;
        }
        var minLength = Math.min(a.length, b.length);
        var maxLength = Math.max(a.length, b.length);
        if (minLength === 0) {
            return 0;
        }
        if (a.indexOf(b) >= 0 || b.indexOf(a) >= 0) {
            return minLength / maxLength;
        }
        return diceCoefficient(a, b);
    }

    /**
     * @brief 计算两个字符串的二元组 Dice 系数。
     * @param a 第一个比较值。
     * @param b 第二个比较值。
     * @return 范围为 0 到 1 的相似度。
     */
    function diceCoefficient(a, b) {
        if (a.length < 2 || b.length < 2) {
            return a === b ? 1 : 0;
        }

        var counts = {};
        var x;
        for (x = 0; x < a.length - 1; x++) {
            var gramA = a.substring(x, x + 2);
            counts[gramA] = (counts[gramA] || 0) + 1;
        }

        var intersection = 0;
        for (x = 0; x < b.length - 1; x++) {
            var gramB = b.substring(x, x + 2);
            if (counts[gramB]) {
                counts[gramB]--;
                intersection++;
            }
        }

        return (2 * intersection) / ((a.length - 1) + (b.length - 1));
    }

    /**
     * @brief 规范化文章标题以便执行模糊匹配。
     * @param value 待处理值。
     * @return 移除格式和分隔符后的标题。
     */
    function normalizeTitle(value) {
        var text = String(value || "").toLowerCase();
        text = text.replace(/<[^>]*>/g, "");
        text = text.replace(/[`*_~#]/g, "");
        text = text.replace(/[\s\-_\u2014\u2013:：,，.。!?！？'\"“”‘’()（）\[\]【】<>《》|\/\\]+/g, "");
        return text;
    }

    /**
     * @brief 验证 URL 是否为允许的 CSDN 文章地址。
     * @param url 待请求或验证的 URL。
     * @return 地址合法时返回 true。
     */
    function isAllowedCsdnArticleUrl(url) {
        return /^https:\/\/(?:blog\.csdn\.net\/[^\/]+|[^\.\/]+\.blog\.csdn\.net)\/article\/details\/\d+(?:[/?#].*)?$/i.test(url);
    }

    /**
     * @brief 将 CSDN 文章列表保存到本地缓存。
     * @param path 文件路径。
     * @param articles 文章对象数组。
     * @return 无。
     */
    function saveCsdnCache(path, articles) {
        var cacheLines = [];
        cacheLines.push("# Generate-Directory CSDN cache v1");
        for (var q = 0; q < articles.length; q++) {
            var safeUrl = String(articles[q].url).replace(/[\t\r\n]/g, "");
            var safeTitle = String(articles[q].title).replace(/[\t\r\n]/g, " ");
            cacheLines.push(safeUrl + "\t" + safeTitle);
        }
        writeUtf8(path, cacheLines.join("\r\n") + "\r\n");
    }

    /**
     * @brief 从本地缓存加载 CSDN 文章列表。
     * @param path 文件路径。
     * @return 文章对象数组。
     */
    function loadCsdnCache(path) {
        var text = readUtf8(path).replace(/^\uFEFF/, "");
        var cacheLines = text.split(/\r\n|\n|\r/);
        var articles = [];
        for (var r = 0; r < cacheLines.length; r++) {
            var line = cacheLines[r];
            if (!line || line.charAt(0) === "#") {
                continue;
            }
            var tab = line.indexOf("\t");
            if (tab <= 0) {
                continue;
            }
            var url = line.substring(0, tab);
            var title = line.substring(tab + 1);
            if (title && isAllowedCsdnArticleUrl(url)) {
                articles.push({ title: title, url: url });
            }
        }
        return articles;
    }

    /**
     * @brief 读取 UTF-8 文本文件。
     * @param path 文件路径。
     * @return 解码后的文本。
     * @throws 文件无法读取或解码时抛出异常。
     */
    function readUtf8(path) {
        return readUtf8FileInfo(path).text;
    }

    /**
     * @brief 读取 UTF-8 文件并记录原文件是否包含 BOM。
     * @param path 文件路径。
     * @return 包含 text 和 hasBom 字段的文件信息对象。
     * @throws 文件无法读取或解码时抛出异常。
     */
    function readUtf8FileInfo(path) {
        var stream = new ActiveXObject("ADODB.Stream");
        stream.Type = 1;
        stream.Open();
        stream.LoadFromFile(path);

        var hasBom = false;
        if (stream.Size >= 3) {
            // 使用 Windows-1252 临时解码前三个原始字节，避免依赖部分 WSH 环境不提供的 VBArray。
            stream.Position = 0;
            stream.Type = 2;
            stream.Charset = "windows-1252";
            var prefix = stream.ReadText(3);
            hasBom = prefix.length >= 3 &&
                prefix.charCodeAt(0) === 0xEF &&
                prefix.charCodeAt(1) === 0xBB &&
                prefix.charCodeAt(2) === 0xBF;
        }

        // 切换字符集前必须把流位置复位到开头。
        stream.Position = 0;
        stream.Type = 2;
        stream.Charset = "utf-8";
        var text = stream.ReadText();
        stream.Close();

        // ADODB.Stream 通常会移除 BOM；此处只防止 BOM 被作为正文字符返回。
        if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
            text = text.substring(1);
        }

        return { text: text, hasBom: hasBom };
    }

    /**
     * @brief 以 UTF-8 编码写入生成文件。
     * @param path 输出文件路径。
     * @param text 待写入文本。
     * @return 无。
     * @throws 文件无法创建或写入时抛出异常。
     */
    function writeUtf8(path, text) {
        var stream = new ActiveXObject("ADODB.Stream");
        stream.Type = 2;
        stream.Charset = "utf-8";
        stream.Open();
        stream.WriteText(text);
        stream.SaveToFile(path, 2);
        stream.Close();
    }

    /**
     * @brief 以 UTF-8 写回文章，并保持原文件的 BOM 状态。
     * @param path 文章文件路径。
     * @param text 待写回文本。
     * @param hasBom 原文件包含 UTF-8 BOM 时为 true。
     * @return 无。
     * @throws 文件无法写入时抛出异常。
     */
    function writeUtf8PreservingBom(path, text, hasBom) {
        var utf8Stream = new ActiveXObject("ADODB.Stream");
        utf8Stream.Type = 2;
        utf8Stream.Charset = "utf-8";
        utf8Stream.Open();
        utf8Stream.WriteText(text);
        utf8Stream.Position = 0;
        utf8Stream.Type = 1;

        if (hasBom) {
            utf8Stream.SaveToFile(path, 2);
            utf8Stream.Close();
            return;
        }

        var outputStream = new ActiveXObject("ADODB.Stream");
        outputStream.Type = 1;
        outputStream.Open();

        // ADODB.Stream 生成 UTF-8 文本时会自动写入 3 字节 BOM；无 BOM 文件写回时跳过它。
        if (utf8Stream.Size >= 3) {
            utf8Stream.Position = 3;
        }
        utf8Stream.CopyTo(outputStream);
        outputStream.SaveToFile(path, 2);

        outputStream.Close();
        utf8Stream.Close();
    }

    /**
     * @brief 清理 YAML 标量两端空白和成对引号。
     * @param value 待处理值。
     * @return 清理后的标量。
     */
    function cleanYamlScalar(value) {
        var text = String(value || "").replace(/^\s+|\s+$/g, "");
        if (text.length >= 2) {
            var first = text.charAt(0);
            var last = text.charAt(text.length - 1);
            if ((first === "\"" && last === "\"") || (first === "'" && last === "'")) {
                text = text.substring(1, text.length - 1);
            }
        }
        return text.replace(/^\s+|\s+$/g, "");
    }

    /**
     * @brief 清理用于目录显示的文章标题。
     * @param value 待处理值。
     * @return 清理后的标题。
     */
    function cleanDisplayTitle(value) {
        var text = String(value || "").replace(/^\s+|\s+$/g, "");
        text = text.replace(/\s+#+\s*$/, "");
        return text;
    }

    /**
     * @brief 对相对路径的各路径段进行 URL 编码。
     * @param path 文件路径。
     * @return 编码后的相对路径。
     */
    function encodeRelativePath(path) {
        var normalized = String(path).replace(/\\/g, "/");
        var segments = normalized.split("/");
        for (var s = 0; s < segments.length; s++) {
            segments[s] = encodeURIComponent(segments[s]).replace(/%2F/gi, "/");
        }
        return segments.join("/");
    }

    /**
     * @brief 转义 Markdown 链接标签中的特殊字符。
     * @param value 待处理值。
     * @return 转义后的标签文本。
     */
    function escapeMarkdownLabel(value) {
        return String(value).replace(/\\/g, "\\\\").replace(/\[/g, "\\[").replace(/\]/g, "\\]");
    }

    /**
     * @brief 将 Windows Script Host 集合转换为数组。
     * @param collection WSH 集合对象。
     * @return 普通 JScript 数组。
     */
    function collectionToArray(collection) {
        var array = [];
        var enumerator = new Enumerator(collection);
        for (; !enumerator.atEnd(); enumerator.moveNext()) {
            array.push(enumerator.item());
        }
        return array;
    }

    /**
     * @brief 按名称执行不区分大小写的排序比较。
     * @param a 第一个比较值。
     * @param b 第二个比较值。
     * @return 小于、等于或大于零的比较结果。
     */
    function compareByName(a, b) {
        var aa = String(a.Name).toLowerCase();
        var bb = String(b.Name).toLowerCase();
        if (aa < bb) {
            return -1;
        }
        if (aa > bb) {
            return 1;
        }
        return 0;
    }

    /**
     * @brief 重复拼接指定字符串。
     * @param text 待处理文本。
     * @param count 重复次数。
     * @return 重复后的字符串。
     */
    function repeat(text, count) {
        var output = "";
        for (var t = 0; t < count; t++) {
            output += text;
        }
        return output;
    }

    /**
     * @brief 将源数组的元素追加到目标数组。
     * @param target 目标数组。
     * @param source 源数组。
     * @return 无。
     */
    function appendArray(target, source) {
        for (var u = 0; u < source.length; u++) {
            target.push(source[u]);
        }
    }

    /**
     * @brief 比较两个路径是否指向同一位置。
     * @param a 第一个比较值。
     * @param b 第二个比较值。
     * @return 路径相同时返回 true。
     */
    function samePath(a, b) {
        return fso.GetAbsolutePathName(a).toLowerCase() === fso.GetAbsolutePathName(b).toLowerCase();
    }

    /**
     * @brief 移除文件名的最后一个扩展名。
     * @param name 文件名。
     * @return 不含扩展名的文件名。
     */
    function removeExtension(name) {
        var dot = String(name).lastIndexOf(".");
        return dot > 0 ? String(name).substring(0, dot) : String(name);
    }

    /**
     * @brief 替换 Windows 文件名中的非法字符。
     * @param name 文件名。
     * @return 可用作输出文件名的字符串。
     */
    function sanitizeFileName(name) {
        var safe = String(name).replace(/[\\\/:*?\"<>|]/g, "_");
        safe = safe.replace(/[\. ]+$/, "");
        return safe || "Study-Notes.md";
    }

    /**
     * @brief 确保 URL 以斜杠结尾。
     * @param url 待请求或验证的 URL。
     * @return 带结尾斜杠的 URL。
     */
    function ensureTrailingSlash(url) {
        return /\/$/.test(url) ? url : (url + "/");
    }

    /**
     * @brief 移除字符串首尾成对双引号。
     * @param value 待处理值。
     * @return 处理后的字符串。
     */
    function stripOuterQuotes(value) {
        var text = String(value || "");
        if (text.length >= 2 && text.charAt(0) === "\"" && text.charAt(text.length - 1) === "\"") {
            return text.substring(1, text.length - 1);
        }
        return text;
    }

    /**
     * @brief 解析非负整数，失败时使用回退值。
     * @param value 待处理值。
     * @param fallback 解析失败时使用的回退值。
     * @return 解析结果或回退值。
     */
    function parsePositiveInt(value, fallback) {
        var parsed = parseInt(value, 10);
        return isNaN(parsed) || parsed < 0 ? fallback : parsed;
    }

    /**
     * @brief 从异常对象中提取可显示的错误信息。
     * @param error 函数输入参数。
     * @return 错误描述字符串。
     */
    function safeError(error) {
        if (!error) {
            return "unknown error";
        }
        return error.description || error.message || String(error);
    }
}());
