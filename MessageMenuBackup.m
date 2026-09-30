#import "MessageMenuBackup.h"
#import "MessageMenuConfig.h"

#import <Foundation/Foundation.h>
#import <ctype.h>
#import <limits.h>
#import <stdint.h>
#import <string.h>
#import <zlib.h>

NSString * const MMMenuBackupFilename = @"MessageMenu_backup.zip";

static NSString * const kMMBackupEntryName = @"MessageMenu.json";
static NSUInteger const kMMBackupMaxBytes = 2 * 1024 * 1024;

static NSError *MMBackupError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"MessageMenu.Backup"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @"备份操作失败"}];
}
static void MMAppendLE16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = {(uint8_t)(value & 0xff), (uint8_t)((value >> 8) & 0xff)};
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void MMAppendLE32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = {(uint8_t)(value & 0xff), (uint8_t)((value >> 8) & 0xff),
                        (uint8_t)((value >> 16) & 0xff), (uint8_t)((value >> 24) & 0xff)};
    [data appendBytes:bytes length:sizeof(bytes)];
}

static uint32_t MMCRC32(NSData *data) {
    static uint32_t table[256];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t value = i;
            for (NSUInteger bit = 0; bit < 8; bit++) {
                value = (value & 1) ? (value >> 1) ^ 0xedb88320U : value >> 1;
            }
            table[i] = value;
        }
    });

    const uint8_t *bytes = data.bytes;
    uint32_t crc = 0xffffffffU;
    for (NSUInteger i = 0; i < data.length; i++) {
        crc = table[(crc ^ bytes[i]) & 0xff] ^ (crc >> 8);
    }
    return crc ^ 0xffffffffU;
}

/// MS-DOS timestamps have no zero value: a date field of 0 means day 0 of
/// month 0 of 1980, which strict readers reject. Emit the real modification
/// time so every unzip implementation accepts the archive.
static void MMDOSTimestamp(uint16_t *dosTime, uint16_t *dosDate) {
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *parts = [calendar components:
        NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
        NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
                                          fromDate:[NSDate date]];
    NSInteger year = MAX(parts.year, (NSInteger)1980);
    if (dosDate) {
        *dosDate = (uint16_t)(((year - 1980) << 9) | (parts.month << 5) | parts.day);
    }
    if (dosTime) {
        *dosTime = (uint16_t)((parts.hour << 11) | (parts.minute << 5) | (parts.second / 2));
    }
}

// A small "store" ZIP writer is sufficient here and avoids adding a third
// party dependency to a tweak. The archive is accepted by Files and WeChat.
static NSData *MMZipArchive(NSData *payload, NSString *filename) {
    NSData *nameData = [filename dataUsingEncoding:NSUTF8StringEncoding];
    if (!nameData || nameData.length > UINT16_MAX || payload.length > UINT32_MAX) return nil;

    uint16_t dosTime = 0, dosDate = 0;
    MMDOSTimestamp(&dosTime, &dosDate);
    uint32_t crc = MMCRC32(payload);
    uint32_t size = (uint32_t)payload.length;
    NSMutableData *zip = [NSMutableData data];
    uint32_t localOffset = (uint32_t)zip.length;

    MMAppendLE32(zip, 0x04034b50U);
    MMAppendLE16(zip, 20);              // version needed
    MMAppendLE16(zip, 0);               // flags
    MMAppendLE16(zip, 0);               // stored (no compression)
    MMAppendLE16(zip, dosTime);
    MMAppendLE16(zip, dosDate);
    MMAppendLE32(zip, crc);
    MMAppendLE32(zip, size);
    MMAppendLE32(zip, size);
    MMAppendLE16(zip, (uint16_t)nameData.length);
    MMAppendLE16(zip, 0);
    [zip appendData:nameData];
    [zip appendData:payload];

    uint32_t centralOffset = (uint32_t)zip.length;
    MMAppendLE32(zip, 0x02014b50U);
    MMAppendLE16(zip, 20);              // creator version
    MMAppendLE16(zip, 20);              // version needed
    MMAppendLE16(zip, 0);
    MMAppendLE16(zip, 0);
    MMAppendLE16(zip, dosTime);
    MMAppendLE16(zip, dosDate);
    MMAppendLE32(zip, crc);
    MMAppendLE32(zip, size);
    MMAppendLE32(zip, size);
    MMAppendLE16(zip, (uint16_t)nameData.length);
    MMAppendLE16(zip, 0);
    MMAppendLE16(zip, 0);
    MMAppendLE16(zip, 0);
    MMAppendLE16(zip, 0);
    MMAppendLE32(zip, 0);
    MMAppendLE32(zip, localOffset);
    [zip appendData:nameData];

    uint32_t centralSize = (uint32_t)zip.length - centralOffset;
    MMAppendLE32(zip, 0x06054b50U);
    MMAppendLE16(zip, 0);
    MMAppendLE16(zip, 0);
    MMAppendLE16(zip, 1);
    MMAppendLE16(zip, 1);
    MMAppendLE32(zip, centralSize);
    MMAppendLE32(zip, centralOffset);
    MMAppendLE16(zip, 0);
    return [zip copy];
}

static NSDictionary *MMBackupDictionary(void) {
    return @{
        @"format": @1,
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"enabled": @(MMMenuIsEnabled()),
        @"sortingEnabled": @(MMMenuIsSortingEnabled()),
        @"pluginTitle": MMMenuPluginTitle() ?: @"",
        @"pluginVersion": MMMenuPluginVersion() ?: @"",
        @"entries": MMMenuLoadEntries() ?: @[],
    };
}

static NSData *MMBackupJSONData(NSError **error) {
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:MMBackupDictionary()
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:&jsonError];
    if (!data && error) *error = jsonError ?: MMBackupError(1, @"无法生成备份内容");
    return data;
}

NSURL *MMMenuCreateBackupFile(NSError **error) {
    NSError *jsonError = nil;
    NSData *json = MMBackupJSONData(&jsonError);
    if (!json) {
        if (error) *error = jsonError;
        return nil;
    }

    NSData *archive = MMZipArchive(json, kMMBackupEntryName);
    if (!archive) {
        if (error) *error = MMBackupError(2, @"无法打包备份文件");
        return nil;
    }

    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MessageMenu"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createDirectoryAtPath:directory
                withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    NSString *path = [directory stringByAppendingPathComponent:MMMenuBackupFilename];
    NSError *writeError = nil;
    if (![archive writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        if (error) *error = writeError ?: MMBackupError(3, @"无法写入备份文件");
        return nil;
    }
    return [NSURL fileURLWithPath:path];
}

NSURL *MMMenuLatestBackupURL(void) {
    NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"MessageMenu"]
                       stringByAppendingPathComponent:MMMenuBackupFilename];
    return [[NSFileManager defaultManager] fileExistsAtPath:path]
        ? [NSURL fileURLWithPath:path] : nil;
}

BOOL MMMenuIsBackupFilename(NSString *filename) {
    NSString *name = [filename.lastPathComponent stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [name caseInsensitiveCompare:MMMenuBackupFilename] == NSOrderedSame;
}

static uint32_t MMReadLE32(const uint8_t *bytes, NSUInteger length, NSUInteger offset, BOOL *ok) {
    if (offset > length || length - offset < 4) {
        if (ok) *ok = NO;
        return 0;
    }
    if (ok) *ok = YES;
    return (uint32_t)bytes[offset] | ((uint32_t)bytes[offset + 1] << 8) |
           ((uint32_t)bytes[offset + 2] << 16) | ((uint32_t)bytes[offset + 3] << 24);
}

static uint16_t MMReadLE16(const uint8_t *bytes, NSUInteger length, NSUInteger offset, BOOL *ok) {
    if (offset > length || length - offset < 2) {
        if (ok) *ok = NO;
        return 0;
    }
    if (ok) *ok = YES;
    return (uint16_t)bytes[offset] | ((uint16_t)bytes[offset + 1] << 8);
}

static BOOL MMZipFindEndRecord(NSData *archive, NSUInteger *offsetOut) {
    if (archive.length < 22) return NO;

    // The EOCD record is followed by at most a 65,535-byte ZIP comment.
    NSUInteger start = archive.length > (22 + UINT16_MAX)
        ? archive.length - (22 + UINT16_MAX) : 0;
    const uint8_t *bytes = archive.bytes;
    for (NSUInteger offset = archive.length - 22;; offset--) {
        if (MMReadLE32(bytes, archive.length, offset, NULL) == 0x06054b50U) {
            BOOL ok = NO;
            uint16_t commentLength = MMReadLE16(bytes, archive.length, offset + 20, &ok);
            if (ok && commentLength == archive.length - offset - 22) {
                if (offsetOut) *offsetOut = offset;
                return YES;
            }
        }
        if (offset == start) break;
    }
    return NO;
}

static NSData *MMInflateZipEntry(NSData *compressed,
                                 NSUInteger expectedLength,
                                 NSError **error) {
    if (expectedLength > kMMBackupMaxBytes) {
        if (error) *error = MMBackupError(5, @"备份配置内容过大");
        return nil;
    }

    // MessageMenu archives are small. Allocate the advertised size and grow
    // only when a producer omitted it or supplied a conservative value.
    NSUInteger capacity = MAX(expectedLength, (NSUInteger)1);
    NSMutableData *output = [NSMutableData dataWithLength:capacity];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)compressed.bytes;
    stream.avail_in = (uInt)MIN(compressed.length, (NSUInteger)UINT_MAX);
    int result = inflateInit2(&stream, -MAX_WBITS); // ZIP uses raw DEFLATE.
    if (result != Z_OK) {
        if (error) *error = MMBackupError(6, @"无法解压备份配置");
        return nil;
    }

    while (YES) {
        stream.next_out = (Bytef *)output.mutableBytes + stream.total_out;
        stream.avail_out = (uInt)(output.length - stream.total_out);
        result = inflate(&stream, Z_NO_FLUSH);
        if (result == Z_STREAM_END) break;
        if (result != Z_OK) {
            inflateEnd(&stream);
            if (error) *error = MMBackupError(6, @"备份配置已损坏，无法解压");
            return nil;
        }
        if (stream.avail_out != 0) continue;
        if (output.length >= kMMBackupMaxBytes) {
            inflateEnd(&stream);
            if (error) *error = MMBackupError(5, @"备份配置内容过大");
            return nil;
        }
        NSUInteger nextLength = MIN(output.length * 2, kMMBackupMaxBytes);
        [output increaseLengthBy:nextLength - output.length];
    }

    NSUInteger actualLength = stream.total_out;
    inflateEnd(&stream);
    if (expectedLength != 0 && actualLength != expectedLength) {
        if (error) *error = MMBackupError(6, @"备份配置已损坏，大小校验失败");
        return nil;
    }
    [output setLength:actualLength];
    return [output copy];
}

static NSData *MMExtractZipEntry(NSData *archive,
                                 NSUInteger localOffset,
                                 uint16_t centralFlags,
                                 uint16_t centralMethod,
                                 uint32_t expectedCRC,
                                 uint32_t compressedLength,
                                 uint32_t uncompressedLength,
                                 NSError **error) {
    const uint8_t *bytes = archive.bytes;
    BOOL ok = NO;
    if (localOffset > archive.length || archive.length - localOffset < 30 ||
        MMReadLE32(bytes, archive.length, localOffset, &ok) != 0x04034b50U) {
        if (error) *error = MMBackupError(7, @"备份文件已损坏，找不到配置条目");
        return nil;
    }

    uint16_t localFlags = MMReadLE16(bytes, archive.length, localOffset + 6, &ok);
    uint16_t localMethod = MMReadLE16(bytes, archive.length, localOffset + 8, &ok);
    uint16_t nameLength = MMReadLE16(bytes, archive.length, localOffset + 26, &ok);
    uint16_t extraLength = MMReadLE16(bytes, archive.length, localOffset + 28, &ok);
    if (!ok || (centralFlags & 0x01) != 0 || (localFlags & 0x01) != 0 ||
        localMethod != centralMethod) {
        if (error) *error = MMBackupError(8, @"备份配置使用了不支持的压缩格式");
        return nil;
    }

    NSUInteger dataOffset = localOffset + 30 + nameLength + extraLength;
    if (dataOffset > archive.length || compressedLength > archive.length - dataOffset ||
        uncompressedLength > kMMBackupMaxBytes) {
        if (error) *error = MMBackupError(7, @"备份文件已损坏，配置条目不完整");
        return nil;
    }
    NSData *payload = [NSData dataWithBytes:bytes + dataOffset length:compressedLength];
    NSData *result = nil;
    if (centralMethod == 0) {
        if (compressedLength != uncompressedLength) {
            if (error) *error = MMBackupError(7, @"备份配置大小校验失败");
            return nil;
        }
        result = payload;
    } else if (centralMethod == 8) {
        result = MMInflateZipEntry(payload, uncompressedLength, error);
    } else {
        if (error) *error = MMBackupError(8, @"备份配置使用了不支持的压缩格式");
        return nil;
    }
    if (result && MMCRC32(result) != expectedCRC) {
        if (error) *error = MMBackupError(7, @"备份配置已损坏，内容校验失败");
        return nil;
    }
    return result;
}

static NSData *MMExtractBackupJSON(NSData *archive, NSError **error) {
    if (archive.length > kMMBackupMaxBytes) {
        if (error) *error = MMBackupError(4, @"备份文件过大");
        return nil;
    }

    const uint8_t *bytes = archive.bytes;
    // Accept a plain JSON export as a convenience for manually edited files,
    // but never treat arbitrary text as a valid configuration.
    NSUInteger first = 0;
    while (first < archive.length && isspace(bytes[first])) first++;
    if (first < archive.length && bytes[first] == '{') {
        return [NSData dataWithBytes:bytes + first length:archive.length - first];
    }

    NSUInteger endOffset = 0;
    if (!MMZipFindEndRecord(archive, &endOffset)) {
        if (error) *error = MMBackupError(7, @"无法读取 ZIP 文件，请选择有效的备份文件");
        return nil;
    }

    BOOL ok = NO;
    uint16_t entries = MMReadLE16(bytes, archive.length, endOffset + 10, &ok);
    uint32_t centralSize = MMReadLE32(bytes, archive.length, endOffset + 12, &ok);
    uint32_t centralOffset = MMReadLE32(bytes, archive.length, endOffset + 16, &ok);
    if (!ok || centralOffset > archive.length || centralSize > archive.length - centralOffset ||
        centralOffset > endOffset || centralSize > endOffset - centralOffset) {
        if (error) *error = MMBackupError(7, @"备份文件已损坏，目录信息不可读");
        return nil;
    }

    NSUInteger offset = centralOffset;
    for (NSUInteger index = 0; index < entries; index++) {
        if (offset > archive.length || archive.length - offset < 46 ||
            MMReadLE32(bytes, archive.length, offset, &ok) != 0x02014b50U) {
            if (error) *error = MMBackupError(7, @"备份文件已损坏，目录信息不可读");
            return nil;
        }

        uint16_t flags = MMReadLE16(bytes, archive.length, offset + 8, &ok);
        uint16_t method = MMReadLE16(bytes, archive.length, offset + 10, &ok);
        uint32_t crc = MMReadLE32(bytes, archive.length, offset + 16, &ok);
        uint32_t compressed = MMReadLE32(bytes, archive.length, offset + 20, &ok);
        uint32_t uncompressed = MMReadLE32(bytes, archive.length, offset + 24, &ok);
        uint16_t nameLength = MMReadLE16(bytes, archive.length, offset + 28, &ok);
        uint16_t extraLength = MMReadLE16(bytes, archive.length, offset + 30, &ok);
        uint16_t commentLength = MMReadLE16(bytes, archive.length, offset + 32, &ok);
        uint32_t localOffset = MMReadLE32(bytes, archive.length, offset + 42, &ok);
        NSUInteger recordLength = 46 + nameLength + extraLength + commentLength;
        if (!ok || recordLength > archive.length - offset) {
            if (error) *error = MMBackupError(7, @"备份文件已损坏，目录信息不可读");
            return nil;
        }

        NSString *name = [[NSString alloc] initWithBytes:bytes + offset + 46
                                                   length:nameLength
                                                 encoding:NSUTF8StringEncoding];
        if ([name.lastPathComponent isEqualToString:kMMBackupEntryName]) {
            return MMExtractZipEntry(archive, localOffset, flags, method, crc,
                                     compressed, uncompressed, error);
        }
        offset += recordLength;
    }

    if (error) *error = MMBackupError(13,
                                      @"这个 ZIP 文件内没有 MessageMenu 配置信息。请选择由本插件生成的 MessageMenu_backup.zip。");
    return nil;
}

BOOL MMMenuRestoreFromBackupData(NSData *data, NSError **error) {
    if (error) *error = nil;
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        if (error) *error = MMBackupError(8, @"备份内容为空");
        return NO;
    }
    NSData *jsonData = MMExtractBackupJSON(data, error);
    if (!jsonData) return NO;

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error) *error = jsonError ?: MMBackupError(9, @"备份内容不是有效配置");
        return NO;
    }
    NSDictionary *dictionary = (NSDictionary *)object;
    id rawEntries = dictionary[@"entries"];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    if ([rawEntries isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)rawEntries) {
            if (![value isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *rawEntry = value;
            NSString *title = MMMenuNormalizeTitle(rawEntry[MMMenuEntryTitleKey]);
            if (!title) continue;

            NSMutableDictionary *entry = [@{
                MMMenuEntryTitleKey: title,
                MMMenuEntryRemoveKey: @([rawEntry[MMMenuEntryRemoveKey]
                                          respondsToSelector:@selector(boolValue)]
                    ? [rawEntry[MMMenuEntryRemoveKey] boolValue] : NO),
                MMMenuEntryBuiltinKey: @([rawEntry[MMMenuEntryBuiltinKey]
                                           respondsToSelector:@selector(boolValue)]
                    ? [rawEntry[MMMenuEntryBuiltinKey] boolValue] : NO),
            } mutableCopy];
            NSString *identifier = MMMenuNormalizeTitle(rawEntry[MMMenuEntryIdentifierKey]);
            if (identifier) entry[MMMenuEntryIdentifierKey] = identifier;
            [entries addObject:[entry copy]];
        }
    }
    if (!entries.count) {
        if (error) *error = MMBackupError(10,
                                          @"这个 ZIP 文件内没有有效的 MessageMenu 菜单配置，无法还原。");
        return NO;
    }

    MMMenuSaveEntries(entries);
    id enabled = dictionary[@"enabled"];
    if ([enabled respondsToSelector:@selector(boolValue)]) {
        MMMenuSetEnabled([enabled boolValue]);
    }
    id sortingEnabled = dictionary[@"sortingEnabled"];
    if ([sortingEnabled respondsToSelector:@selector(boolValue)]) {
        MMMenuSetSortingEnabled([sortingEnabled boolValue]);
    }
    MMMenuSetPluginIdentity(dictionary[@"pluginTitle"], dictionary[@"pluginVersion"]);
    MMMenuUpdatePluginManagerRegistration();
    return YES;
}

BOOL MMMenuRestoreFromBackupURL(NSURL *url, NSError **error) {
    if (!url) {
        if (error) *error = MMBackupError(11, @"没有选择备份文件");
        return NO;
    }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
    if (!data && error) *error = readError ?: MMBackupError(12, @"无法读取备份文件");
    BOOL result = data ? MMMenuRestoreFromBackupData(data, error) : NO;
    if (scoped) [url stopAccessingSecurityScopedResource];
    return result;
}

void MMMenuCreateBackupFileAsync(void (^completion)(NSURL *url, NSString *errorMessage)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSURL *url = MMMenuCreateBackupFile(&error);
        NSString *message = url ? nil : (error.localizedDescription ?: @"备份失败");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(url, message);
        });
    });
}
