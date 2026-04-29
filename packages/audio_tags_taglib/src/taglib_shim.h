#ifndef TAGLIB_SHIM_H
#define TAGLIB_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Return the TagLib version string (e.g. "2.2.1").
 *
 * The returned pointer is to a static string — callers must NOT pass it to
 * taglib_free_string.
 */
const char* taglib_version(void);

/**
 * Return a human-readable description of the most recent failure raised by
 * taglib_read_file or taglib_write_file. Returns "" if no error has been
 * recorded.
 *
 * The returned pointer is to thread-local storage and remains valid until the
 * next shim call on the same thread. Callers must NOT free it.
 */
const char* taglib_last_error(void);

/**
 * Read metadata from an audio file.
 *
 * @param path           Null-terminated UTF-8 file path.
 * @param read_props     1 to include audio properties, 0 to skip.
 * @param read_pictures  1 to include embedded pictures, 0 to skip.
 * @param read_chapters  1 to include chapter markers (ID3v2 CHAP), 0 to skip.
 * @param read_raw_tags  1 to include raw tag fields, 0 to skip.
 * @return A heap-allocated JSON string on success, NULL on failure.
 *         Caller must free with taglib_free_string().
 *         On NULL, call taglib_last_error() for the reason.
 */
char* taglib_read_file(
    const char* path,
    int read_props,
    int read_pictures,
    int read_chapters,
    int read_raw_tags
);

/**
 * Write metadata to an audio file.
 *
 * @param path       Null-terminated UTF-8 file path.
 * @param patch_json Null-terminated JSON string describing the patch.
 * @return 0 on success, negative error code on failure:
 *           -1: file not found / open failed
 *           -2: unsupported format
 *           -3: invalid patch JSON
 *           -4: save failed
 *           -5: picture op failed
 *         Call taglib_last_error() for a human-readable description.
 */
int taglib_write_file(const char* path, const char* patch_json);

/**
 * Free a string previously returned by taglib_read_file.
 */
void taglib_free_string(char* str);

#ifdef __cplusplus
}
#endif

#endif /* TAGLIB_SHIM_H */
