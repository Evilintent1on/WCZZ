#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// The filename is intentionally stable so a backup can be recognised when a
/// user long-presses it in the File Transfer Assistant conversation.
FOUNDATION_EXPORT NSString * const MMMenuBackupFilename;

FOUNDATION_EXPORT NSURL * _Nullable MMMenuCreateBackupFile(NSError **error);
FOUNDATION_EXPORT NSURL * _Nullable MMMenuLatestBackupURL(void);
FOUNDATION_EXPORT BOOL MMMenuIsBackupFilename(NSString * _Nullable filename);
FOUNDATION_EXPORT BOOL MMMenuRestoreFromBackupData(NSData *data, NSError **error);
FOUNDATION_EXPORT BOOL MMMenuRestoreFromBackupURL(NSURL *url, NSError **error);

/// Creates the archive on a background queue and calls back on the main queue
/// with a file URL the caller can hand to a share sheet.
///
/// Earlier versions fabricated a `CMessageWrap` and inserted it straight into
/// the local database. That produced a file bubble with no CDN attachment
/// behind it, so the file could never be downloaded and forwarding it reported
/// “发送中断”. Exporting through the system share sheet makes WeChat perform a
/// real upload instead.
FOUNDATION_EXPORT void MMMenuCreateBackupFileAsync(void (^ _Nullable completion)(NSURL * _Nullable url,
                                                                                  NSString * _Nullable errorMessage));

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
