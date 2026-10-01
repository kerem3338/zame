module zame.tests.vfs_test;

import zame.core.fs;
import zame.core.common;

/// 1. Mount Priority Test
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    
    auto mem1 = new MemoryProvider();
    mem1.saveFile("player.png", cast(ubyte[])"mods");
    
    auto mem2 = new MemoryProvider();
    mem2.saveFile("player.png", cast(ubyte[])"base");
    
    // Mount base first, mods second
    vfs.mount("assets", mem2); // base
    vfs.mount("assets", mem1); // mods
    
    // Read should return 'mods'
    auto res = vfs.readText("assets://player.png");
    assert(res.ok && res.value == "mods", "Mount priority failed. Expected mods, got " ~ (res.ok ? res.value : "error"));
}

/// 2. Provider Isolation Test (Normalization)
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    
    // Assets provider shouldn't escape its mount.
    auto fileProv = new FileProvider("C:/Game");
    vfs.mount("game", fileProv);
    
    auto resolved = vfs.resolve("game://../foo.png");
    assert(resolved.relativePath == "foo.png", "Path normalization failed. Got " ~ resolved.relativePath);
}

/// 3. Absolute path / scheme-less fallback test
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    
    auto fallbackRes = vfs.resolve("C:/MyFile.txt");
    assert(fallbackRes.uri.scheme == "file", "Fallback scheme should be 'file'");
    assert(fallbackRes.provider.name == "FileProvider", "Fallback provider should be FileProvider");
}

/// 4. List Directory Test
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    auto mem = new MemoryProvider();
    mem.saveFile("images/player.png", cast(ubyte[])"img");
    mem.saveFile("images/enemy.png", cast(ubyte[])"img2");
    mem.saveFile("images/bg/sky.png", cast(ubyte[])"img3");
    vfs.mount("assets", mem);
    
    auto entry = vfs.entry("assets://images");
    auto listRes = entry.listDirectory();
    assert(listRes.ok, "List directory failed");
    auto list = listRes.value;
    assert(list.length == 3, "List directory should return 3 items");
    
    int files = 0, dirs = 0;
    foreach(item; list) {
        if (item.type == FsItemType.directory) dirs++;
        else if (item.type == FsItemType.file) files++;
    }
    assert(files == 2, "Should find 2 files");
    assert(dirs == 1, "Should find 1 directory");
}

/// 5. Open Mode Test
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    auto mem = new MemoryProvider();
    vfs.mount("assets", mem);
    
    auto streamRes = vfs.openStream("assets://test.txt", VfsOpenMode.write | VfsOpenMode.binary);
    assert(streamRes.ok, "Failed to open stream for writing");
    auto stream = streamRes.value;
    stream.write(cast(const(ubyte)[])"hello");
    stream.close();
    
    auto readRes = vfs.readText("assets://test.txt");
    assert(readRes.ok && readRes.value == "hello", "Failed to read written text");
}

/// 6. File Management & Byte Reading Test
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    auto mem = new MemoryProvider();
    vfs.mount("temp", mem);
    
    // Test mkdir
    auto mkRes = vfs.mkdir("temp://new_folder");
    assert(mkRes.ok, "mkdir failed");
    
    // Verify it's a directory
    auto entry = vfs.entry("temp://new_folder");
    assert(entry.exists, "new_folder should exist");
    assert(entry.isDirectory, "new_folder should be a directory");
    
    // Write and read bytes
    auto writeRes = vfs.openStream("temp://new_folder/data.bin", VfsOpenMode.write);
    writeRes.value.write(cast(ubyte[])[0x01, 0x02, 0x03]);
    writeRes.value.close();
    
    auto readRes = vfs.readAllBytes("temp://new_folder/data.bin");
    assert(readRes.ok, "readAllBytes failed");
    assert(readRes.value.length == 3 && readRes.value[1] == 0x02, "readAllBytes content mismatch");
    
    // Test remove
    auto rmRes = vfs.remove("temp://new_folder/data.bin");
    assert(rmRes.ok, "remove failed");
    assert(!vfs.entry("temp://new_folder/data.bin").exists, "file should be removed");
}

/// 7. Resolving '.' and Root Paths Test
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    auto mem = vfs.mountMemory("assets");
    mem.saveText("hero.png", "hero data");
    
    // Resolve "." on scheme-less path (should resolve to current directory / default FileProvider)
    auto dotPath = vfs.resolve(".");
    assert(dotPath.exists, "'.' should exist in default file provider");
    assert(dotPath.isDirectory, "'.' should be a directory");
    
    // Resolve root on mount
    auto rootPath = vfs.resolve("assets://");
    assert(rootPath.exists, "assets:// root should exist");
    assert(rootPath.isDirectory, "assets:// root should be a directory");
    
    auto dotMountPath = vfs.resolve("assets://.");
    assert(dotMountPath.exists, "assets://. should exist");
    assert(dotMountPath.isDirectory, "assets://. should be a directory");

    auto dotEntry = vfs.entry("assets://.");
    assert(dotEntry.exists);
    assert(dotEntry.isDirectory);
    assert(dotEntry.name == "assets" || dotEntry.name == "");
}

/// 8. High-Level I/O Helpers (writeText, writeAllBytes, appendText, copy, move)
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    vfs.mountMemory("mem");
    vfs.mountMemory("backup");
    
    // writeText & readText
    auto wRes = vfs.writeText("mem://config.json", `{"sound": true}`);
    assert(wRes.ok, "writeText failed");
    assert(vfs.exists("mem://config.json"), "mem://config.json should exist");
    assert(vfs.isFile("mem://config.json"), "mem://config.json should be a file");
    
    auto rText = vfs.readText("mem://config.json");
    assert(rText.ok && rText.value == `{"sound": true}`);
    
    // appendText
    auto aRes = vfs.appendText("mem://log.txt", "line1\n");
    assert(aRes.ok);
    vfs.appendText("mem://log.txt", "line2\n");
    auto logContent = vfs.readText("mem://log.txt");
    assert(logContent.ok && logContent.value == "line1\nline2\n");
    
    // cross-provider copy
    auto cpRes = vfs.copy("mem://config.json", "backup://config_backup.json");
    assert(cpRes.ok, "cross-provider copy failed");
    assert(vfs.exists("backup://config_backup.json"));
    assert(vfs.readText("backup://config_backup.json").value == `{"sound": true}`);
    
    // cross-provider move
    auto mvRes = vfs.move("backup://config_backup.json", "mem://config_moved.json");
    assert(mvRes.ok, "move failed");
    assert(!vfs.exists("backup://config_backup.json"));
    assert(vfs.exists("mem://config_moved.json"));
}

/// 9. VfsEntry Operator Overloads and Fluent API
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    vfs.mountMemory("assets");
    
    auto root = vfs.entry("assets://");
    auto textures = root / "textures";
    auto hero = textures / "hero.png";
    
    assert(hero.fullPath == "assets://textures/hero.png");
    assert(hero.name == "hero.png");
    assert(hero.baseName == "hero.png");
    assert(hero.extension == ".png");
    
    // Fluent write and read
    hero.writeText("PNG_DATA");
    assert(hero.exists);
    assert(hero.isFile);
    assert(hero.size.ok && hero.size.value == 8);
    assert(hero.readText().value == "PNG_DATA");
    
    // Parent navigation
    auto parentEntry = hero.parent();
    assert(parentEntry.fullPath == "assets://textures");
}

/// 10. Glob Search and File Listing Test
unittest {
    VirtualFileSystem vfs = new VirtualFileSystem();
    auto mem = vfs.mountMemory("game");
    
    mem.saveText("scripts/main.lua", "-- main");
    mem.saveText("scripts/player.lua", "-- player");
    mem.saveText("scripts/ui/hud.lua", "-- hud");
    mem.saveText("sprites/hero.png", "img1");
    mem.saveText("sprites/enemy.png", "img2");
    mem.saveText("readme.txt", "readme");
    
    // Find all lua scripts recursively
    auto luaFiles = vfs.findFiles("game://", "*.lua", true);
    assert(luaFiles.ok);
    assert(luaFiles.value.length == 3, "Should find 3 lua scripts");
    
    // Find png sprites non-recursively in sprites folder
    auto pngFiles = vfs.findFiles("game://sprites", "*.png", false);
    assert(pngFiles.ok);
    assert(pngFiles.value.length == 2, "Should find 2 png files in sprites");
    
    // List direct files in root
    auto rootFiles = vfs.listFiles("game://", false);
    assert(rootFiles.ok);
    assert(rootFiles.value.length == 1, "Root should have 1 direct file (readme.txt)");
}
