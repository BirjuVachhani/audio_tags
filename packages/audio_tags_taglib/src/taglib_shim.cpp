// taglib_shim.cpp
//
// C ABI shim around TagLib for the audio_tags_taglib Dart package.
//
// All metadata is exchanged with Dart as JSON. The shim parses a small subset
// of JSON inline to avoid pulling in a third-party dependency.

#include "taglib_shim.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include <taglib/audioproperties.h>
#include <taglib/fileref.h>
#include <taglib/tag.h>
#include <taglib/taglib.h>
#include <taglib/tbytevector.h>
#include <taglib/tpropertymap.h>

#include <taglib/aifffile.h>
#include <taglib/apefile.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/chapterframe.h>
#include <taglib/flacfile.h>
#include <taglib/flacpicture.h>
#include <taglib/id3v2frame.h>
#include <taglib/id3v2tag.h>
#include <taglib/mp4coverart.h>
#include <taglib/mp4file.h>
#include <taglib/mp4item.h>
#include <taglib/mp4tag.h>
#include <taglib/mpcfile.h>
#include <taglib/mpegfile.h>
#include <taglib/opusfile.h>
#include <taglib/tableofcontentsframe.h>
#include <taglib/textidentificationframe.h>
#include <taglib/vorbisfile.h>
#include <taglib/wavfile.h>
#include <taglib/wavpackfile.h>
#include <taglib/xiphcomment.h>

// ---------------------------------------------------------------------------
// Version — prefer TagLib's compile-time macros, fall back to build define.
// ---------------------------------------------------------------------------

#define _SHIM_STR(x) #x
#define _SHIM_XSTR(x) _SHIM_STR(x)

#if defined(TAGLIB_MAJOR_VERSION) && defined(TAGLIB_MINOR_VERSION) && defined(TAGLIB_PATCH_VERSION)
  #define _TAGLIB_VERSION_STRING \
      _SHIM_XSTR(TAGLIB_MAJOR_VERSION) "." \
      _SHIM_XSTR(TAGLIB_MINOR_VERSION) "." \
      _SHIM_XSTR(TAGLIB_PATCH_VERSION)
#elif defined(SHIM_TAGLIB_VERSION)
  #define _TAGLIB_VERSION_STRING _SHIM_XSTR(SHIM_TAGLIB_VERSION)
#else
  #define _TAGLIB_VERSION_STRING "unknown"
#endif

// ---------------------------------------------------------------------------
// Per-thread error message storage.
// ---------------------------------------------------------------------------

static thread_local std::string t_last_error;
static void set_error(const std::string& msg) { t_last_error = msg; }
static void clear_error() { t_last_error.clear(); }

// ---------------------------------------------------------------------------
// JSON output helpers (minimal, no external dependency)
// ---------------------------------------------------------------------------

static std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            case '\b': out += "\\b";  break;
            case '\f': out += "\\f";  break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

static char* to_heap_string(const std::string& s) {
    char* result = static_cast<char*>(malloc(s.size() + 1));
    if (!result) return nullptr;
    memcpy(result, s.c_str(), s.size() + 1);
    return result;
}

// ---------------------------------------------------------------------------
// Base64 encode / decode for picture payloads.
// ---------------------------------------------------------------------------

static const char kB64Chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::string base64_encode(const unsigned char* data, size_t len) {
    std::string out;
    out.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3) {
        unsigned int n = static_cast<unsigned int>(data[i]) << 16;
        if (i + 1 < len) n |= static_cast<unsigned int>(data[i + 1]) << 8;
        if (i + 2 < len) n |= static_cast<unsigned int>(data[i + 2]);
        out.push_back(kB64Chars[(n >> 18) & 0x3F]);
        out.push_back(kB64Chars[(n >> 12) & 0x3F]);
        out.push_back(i + 1 < len ? kB64Chars[(n >> 6) & 0x3F] : '=');
        out.push_back(i + 2 < len ? kB64Chars[n & 0x3F] : '=');
    }
    return out;
}

static int b64_value(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static std::vector<unsigned char> base64_decode(const std::string& in) {
    std::vector<unsigned char> out;
    out.reserve(in.size() * 3 / 4);
    int buf = 0, bits = 0;
    for (char c : in) {
        if (c == '=' || c == '\n' || c == '\r' || c == ' ' || c == '\t') {
            if (c == '=') break;
            continue;
        }
        int v = b64_value(c);
        if (v < 0) continue;
        buf = (buf << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push_back(static_cast<unsigned char>((buf >> bits) & 0xFF));
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// Tiny JSON parser. Sufficient for the patch protocol (no \uXXXX, no -0,
// fixed UTF-8 input).
// ---------------------------------------------------------------------------

struct JValue {
    enum Type { Null, String, Number, Bool, Object, Array } type = Null;
    std::string str;
    double num = 0;
    bool flag = false;
    std::map<std::string, JValue> obj;
    std::vector<JValue> arr;
};

class JParser {
public:
    explicit JParser(const char* s) : p(s), ok(true) {}
    JValue parse() { skip_ws(); return parse_value(); }
    bool good() const { return ok; }

private:
    const char* p;
    bool ok;

    void skip_ws() {
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') ++p;
    }
    char peek() { skip_ws(); return *p; }
    char next_ch() { skip_ws(); return *p++; }

    int parse_hex4() {
        int v = 0;
        for (int i = 0; i < 4; ++i) {
            char c = *p++;
            int d;
            if (c >= '0' && c <= '9') d = c - '0';
            else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
            else { ok = false; return 0; }
            v = (v << 4) | d;
        }
        return v;
    }

    void encode_utf8(int cp, std::string& s) {
        if (cp < 0x80) {
            s += static_cast<char>(cp);
        } else if (cp < 0x800) {
            s += static_cast<char>(0xC0 | (cp >> 6));
            s += static_cast<char>(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            s += static_cast<char>(0xE0 | (cp >> 12));
            s += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            s += static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            s += static_cast<char>(0xF0 | (cp >> 18));
            s += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
            s += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            s += static_cast<char>(0x80 | (cp & 0x3F));
        }
    }

    std::string parse_string() {
        if (*p != '"') { ok = false; return ""; }
        ++p; // opening "
        std::string s;
        while (*p && *p != '"') {
            if (*p == '\\') {
                ++p;
                switch (*p) {
                    case '"':  s += '"'; ++p; break;
                    case '\\': s += '\\'; ++p; break;
                    case '/':  s += '/'; ++p; break;
                    case 'n':  s += '\n'; ++p; break;
                    case 'r':  s += '\r'; ++p; break;
                    case 't':  s += '\t'; ++p; break;
                    case 'b':  s += '\b'; ++p; break;
                    case 'f':  s += '\f'; ++p; break;
                    case 'u': {
                        ++p;
                        int cp = parse_hex4();
                        if (cp >= 0xD800 && cp <= 0xDBFF && p[0] == '\\' && p[1] == 'u') {
                            p += 2;
                            int low = parse_hex4();
                            if (low >= 0xDC00 && low <= 0xDFFF) {
                                cp = 0x10000 + (((cp - 0xD800) << 10) | (low - 0xDC00));
                            }
                        }
                        encode_utf8(cp, s);
                        break;
                    }
                    default: s += *p; ++p; break;
                }
            } else {
                s += *p++;
            }
        }
        if (*p == '"') ++p;
        return s;
    }

    JValue parse_value() {
        char c = peek();
        if (c == '"') {
            JValue v; v.type = JValue::String; v.str = parse_string(); return v;
        }
        if (c == '{') {
            ++p;
            JValue v; v.type = JValue::Object;
            if (peek() != '}') {
                while (true) {
                    skip_ws();
                    std::string key = parse_string();
                    skip_ws();
                    if (*p != ':') { ok = false; break; }
                    ++p;
                    v.obj[key] = parse_value();
                    if (peek() != ',') break;
                    ++p;
                }
            }
            if (peek() == '}') ++p; else ok = false;
            return v;
        }
        if (c == '[') {
            ++p;
            JValue v; v.type = JValue::Array;
            if (peek() != ']') {
                while (true) {
                    v.arr.push_back(parse_value());
                    if (peek() != ',') break;
                    ++p;
                }
            }
            if (peek() == ']') ++p; else ok = false;
            return v;
        }
        if (c == 't' && p[1] == 'r' && p[2] == 'u' && p[3] == 'e') {
            p += 4; JValue v; v.type = JValue::Bool; v.flag = true; return v;
        }
        if (c == 'f' && p[1] == 'a' && p[2] == 'l' && p[3] == 's' && p[4] == 'e') {
            p += 5; JValue v; v.type = JValue::Bool; v.flag = false; return v;
        }
        if (c == 'n' && p[1] == 'u' && p[2] == 'l' && p[3] == 'l') {
            p += 4; return JValue();
        }
        // number
        JValue v; v.type = JValue::Number;
        char* end = nullptr;
        v.num = strtod(p, &end);
        if (end == p) { ok = false; }
        p = end;
        return v;
    }
};

// ---------------------------------------------------------------------------
// Field name <-> property map key mapping.
// ---------------------------------------------------------------------------

struct FieldMap {
    const char* json;
    const char* property;
};

static const FieldMap kFieldMaps[] = {
    {"title",       "TITLE"},
    {"artist",      "ARTIST"},
    {"album",       "ALBUM"},
    {"albumArtist", "ALBUMARTIST"},
    {"genre",       "GENRE"},
    {"comment",     "COMMENT"},
    {"composer",    "COMPOSER"},
    {"lyricist",    "LYRICIST"},
    {"grouping",    "GROUPING"},
    {"year",        "DATE"},
    {"trackNumber", "TRACKNUMBER"},
    {"trackTotal",  "TRACKTOTAL"},
    {"discNumber",  "DISCNUMBER"},
    {"discTotal",   "DISCTOTAL"},
    {"lyrics",      "LYRICS"},
};

static const char* json_to_property(const std::string& name) {
    for (const auto& m : kFieldMaps) if (name == m.json) return m.property;
    return nullptr;
}

// All upper-case property keys that map to a normalized JSON field — used to
// filter "extras".
static std::set<std::string> kReservedProperties = {
    "TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "GENRE", "COMMENT",
    "COMPOSER", "LYRICIST", "GROUPING", "DATE", "TRACKNUMBER", "TRACKTOTAL",
    "DISCNUMBER", "DISCTOTAL", "LYRICS",
};

// ---------------------------------------------------------------------------
// File-type and container detection.
// ---------------------------------------------------------------------------

struct FileTypeInfo {
    std::string format;     // mp3, flac, ogg-vorbis, opus, mp4, wav, aiff, ape, mpc, wv, ...
    std::string container;  // ID3v2.4, VorbisComments, MP4, RIFF-INFO, APE, ...
};

static std::string id3v2_version_string(const TagLib::ID3v2::Tag* tag) {
    if (!tag) return "ID3v2";
    auto* hdr = tag->header();
    if (!hdr) return "ID3v2";
    int major = hdr->majorVersion();
    int rev = hdr->revisionNumber();
    char buf[16];
    snprintf(buf, sizeof(buf), "ID3v2.%d.%d", major, rev);
    return std::string(buf);
}

static FileTypeInfo detect_file_type(TagLib::File* file) {
    FileTypeInfo info;
    if (!file) return info;

    if (auto* mp3 = dynamic_cast<TagLib::MPEG::File*>(file)) {
        info.format = "mp3";
        if (mp3->hasID3v2Tag()) info.container = id3v2_version_string(mp3->ID3v2Tag());
        else if (mp3->hasAPETag()) info.container = "APE";
        else if (mp3->hasID3v1Tag()) info.container = "ID3v1";
        else info.container = "MPEG";
        return info;
    }
    if (auto* flac = dynamic_cast<TagLib::FLAC::File*>(file)) {
        info.format = "flac";
        if (flac->hasXiphComment()) info.container = "VorbisComments";
        else if (flac->hasID3v2Tag()) info.container = id3v2_version_string(flac->ID3v2Tag());
        else if (flac->hasID3v1Tag()) info.container = "ID3v1";
        else info.container = "FLAC";
        return info;
    }
    if (dynamic_cast<TagLib::MP4::File*>(file)) {
        info.format = "mp4";
        info.container = "MP4";
        return info;
    }
    if (auto* opus = dynamic_cast<TagLib::Ogg::Opus::File*>(file)) {
        (void)opus;
        info.format = "opus";
        info.container = "VorbisComments";
        return info;
    }
    if (auto* vorbis = dynamic_cast<TagLib::Ogg::Vorbis::File*>(file)) {
        (void)vorbis;
        info.format = "ogg-vorbis";
        info.container = "VorbisComments";
        return info;
    }
    if (auto* wav = dynamic_cast<TagLib::RIFF::WAV::File*>(file)) {
        info.format = "wav";
        if (wav->hasID3v2Tag()) info.container = id3v2_version_string(wav->ID3v2Tag());
        else if (wav->hasInfoTag()) info.container = "RIFF-INFO";
        else info.container = "RIFF";
        return info;
    }
    if (auto* aiff = dynamic_cast<TagLib::RIFF::AIFF::File*>(file)) {
        (void)aiff;
        info.format = "aiff";
        info.container = aiff->hasID3v2Tag() ? id3v2_version_string(aiff->tag()) : "AIFF";
        return info;
    }
    if (auto* ape = dynamic_cast<TagLib::APE::File*>(file)) {
        (void)ape;
        info.format = "ape";
        info.container = "APE";
        return info;
    }
    if (auto* mpc = dynamic_cast<TagLib::MPC::File*>(file)) {
        (void)mpc;
        info.format = "mpc";
        info.container = mpc->hasAPETag() ? "APE" : (mpc->hasID3v1Tag() ? "ID3v1" : "MPC");
        return info;
    }
    if (auto* wv = dynamic_cast<TagLib::WavPack::File*>(file)) {
        (void)wv;
        info.format = "wv";
        info.container = wv->hasAPETag() ? "APE" : (wv->hasID3v1Tag() ? "ID3v1" : "WavPack");
        return info;
    }

    info.format = "unknown";
    info.container = "unknown";
    return info;
}

// ---------------------------------------------------------------------------
// Picture extraction per format.
// ---------------------------------------------------------------------------

struct PictureData {
    int type = 0;
    std::string mimeType;
    std::string description;
    TagLib::ByteVector data;
};

// Map MP4 cover art format to a MIME type.
static std::string mp4_cover_mime(TagLib::MP4::CoverArt::Format f) {
    switch (f) {
        case TagLib::MP4::CoverArt::JPEG: return "image/jpeg";
        case TagLib::MP4::CoverArt::PNG:  return "image/png";
        case TagLib::MP4::CoverArt::GIF:  return "image/gif";
        case TagLib::MP4::CoverArt::BMP:  return "image/bmp";
        default: return "";
    }
}

static TagLib::MP4::CoverArt::Format mime_to_mp4_format(const std::string& mime) {
    if (mime == "image/jpeg" || mime == "image/jpg") return TagLib::MP4::CoverArt::JPEG;
    if (mime == "image/png")  return TagLib::MP4::CoverArt::PNG;
    if (mime == "image/gif")  return TagLib::MP4::CoverArt::GIF;
    if (mime == "image/bmp")  return TagLib::MP4::CoverArt::BMP;
    return TagLib::MP4::CoverArt::Unknown;
}

// Sniff MIME type from the magic bytes of an image. Used as a fallback when
// the caller hasn't supplied a mime type.
static std::string sniff_image_mime(const TagLib::ByteVector& data) {
    if (data.size() >= 3 &&
        static_cast<unsigned char>(data[0]) == 0xFF &&
        static_cast<unsigned char>(data[1]) == 0xD8 &&
        static_cast<unsigned char>(data[2]) == 0xFF) {
        return "image/jpeg";
    }
    if (data.size() >= 8 &&
        static_cast<unsigned char>(data[0]) == 0x89 && data[1] == 'P' &&
        data[2] == 'N' && data[3] == 'G') {
        return "image/png";
    }
    if (data.size() >= 6 && data[0] == 'G' && data[1] == 'I' && data[2] == 'F') {
        return "image/gif";
    }
    if (data.size() >= 2 && data[0] == 'B' && data[1] == 'M') {
        return "image/bmp";
    }
    if (data.size() >= 4 &&
        ((data[0] == 'I' && data[1] == 'I') || (data[0] == 'M' && data[1] == 'M'))) {
        return "image/tiff";
    }
    return "application/octet-stream";
}

static std::vector<PictureData> extract_id3v2_pictures(TagLib::ID3v2::Tag* tag) {
    std::vector<PictureData> out;
    if (!tag) return out;
    const auto& frames = tag->frameList("APIC");
    for (auto* f : frames) {
        auto* apic = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame*>(f);
        if (!apic) continue;
        PictureData p;
        p.type = static_cast<int>(apic->type());
        p.mimeType = apic->mimeType().to8Bit(true);
        p.description = apic->description().to8Bit(true);
        p.data = apic->picture();
        out.push_back(std::move(p));
    }
    return out;
}

static std::vector<PictureData> extract_xiph_pictures(TagLib::Ogg::XiphComment* xiph) {
    std::vector<PictureData> out;
    if (!xiph) return out;
    const auto pics = xiph->pictureList();
    for (auto* pic : pics) {
        if (!pic) continue;
        PictureData p;
        p.type = static_cast<int>(pic->type());
        p.mimeType = pic->mimeType().to8Bit(true);
        p.description = pic->description().to8Bit(true);
        p.data = pic->data();
        out.push_back(std::move(p));
    }
    return out;
}

static std::vector<PictureData> extract_flac_pictures(TagLib::FLAC::File* flac) {
    std::vector<PictureData> out;
    if (!flac) return out;
    const auto pics = flac->pictureList();
    for (auto* pic : pics) {
        if (!pic) continue;
        PictureData p;
        p.type = static_cast<int>(pic->type());
        p.mimeType = pic->mimeType().to8Bit(true);
        p.description = pic->description().to8Bit(true);
        p.data = pic->data();
        out.push_back(std::move(p));
    }
    return out;
}

static std::vector<PictureData> extract_mp4_pictures(TagLib::MP4::File* mp4) {
    std::vector<PictureData> out;
    if (!mp4 || !mp4->tag()) return out;
    const auto& items = mp4->tag()->itemMap();
    auto it = items.find("covr");
    if (it == items.end()) return out;
    const auto covers = it->second.toCoverArtList();
    for (const auto& cover : covers) {
        PictureData p;
        // MP4 covers don't expose a type — treat as front cover.
        p.type = 3; // FrontCover
        p.mimeType = mp4_cover_mime(cover.format());
        if (p.mimeType.empty()) p.mimeType = sniff_image_mime(cover.data());
        p.data = cover.data();
        out.push_back(std::move(p));
    }
    return out;
}

static std::vector<PictureData> extract_pictures(TagLib::File* file) {
    if (!file) return {};
    if (auto* mp3 = dynamic_cast<TagLib::MPEG::File*>(file)) {
        if (mp3->hasID3v2Tag()) return extract_id3v2_pictures(mp3->ID3v2Tag());
        return {};
    }
    if (auto* flac = dynamic_cast<TagLib::FLAC::File*>(file)) {
        return extract_flac_pictures(flac);
    }
    if (auto* mp4 = dynamic_cast<TagLib::MP4::File*>(file)) {
        return extract_mp4_pictures(mp4);
    }
    if (auto* vorbis = dynamic_cast<TagLib::Ogg::Vorbis::File*>(file)) {
        return extract_xiph_pictures(vorbis->tag());
    }
    if (auto* opus = dynamic_cast<TagLib::Ogg::Opus::File*>(file)) {
        return extract_xiph_pictures(opus->tag());
    }
    if (auto* wav = dynamic_cast<TagLib::RIFF::WAV::File*>(file)) {
        if (wav->hasID3v2Tag()) return extract_id3v2_pictures(wav->ID3v2Tag());
        return {};
    }
    if (auto* aiff = dynamic_cast<TagLib::RIFF::AIFF::File*>(file)) {
        if (aiff->hasID3v2Tag()) return extract_id3v2_pictures(aiff->tag());
        return {};
    }
    return {};
}

// ---------------------------------------------------------------------------
// Picture write per format.
// ---------------------------------------------------------------------------

enum class PictureOpType { Add, RemoveByType, RemoveAll };

struct PictureOp {
    PictureOpType op;
    int type = 0;          // for RemoveByType, or for Add: picture role
    std::string mimeType;  // for Add
    std::string description; // for Add
    TagLib::ByteVector data; // for Add
};

static int apply_picture_ops_id3v2(TagLib::ID3v2::Tag* tag,
                                   const std::vector<PictureOp>& ops) {
    if (!tag) return -5;
    for (const auto& op : ops) {
        switch (op.op) {
            case PictureOpType::RemoveAll:
                tag->removeFrames("APIC");
                break;
            case PictureOpType::RemoveByType: {
                auto frames = tag->frameList("APIC"); // copy
                for (auto* f : frames) {
                    auto* apic = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame*>(f);
                    if (apic && static_cast<int>(apic->type()) == op.type) {
                        tag->removeFrame(apic);
                    }
                }
                break;
            }
            case PictureOpType::Add: {
                auto* apic = new TagLib::ID3v2::AttachedPictureFrame();
                apic->setType(static_cast<TagLib::ID3v2::AttachedPictureFrame::Type>(op.type));
                std::string mime = op.mimeType.empty() ? sniff_image_mime(op.data) : op.mimeType;
                apic->setMimeType(TagLib::String(mime, TagLib::String::UTF8));
                apic->setDescription(TagLib::String(op.description, TagLib::String::UTF8));
                apic->setPicture(op.data);
                tag->addFrame(apic);
                break;
            }
        }
    }
    return 0;
}

static int apply_picture_ops_xiph(TagLib::Ogg::XiphComment* xiph,
                                  const std::vector<PictureOp>& ops) {
    if (!xiph) return -5;
    for (const auto& op : ops) {
        switch (op.op) {
            case PictureOpType::RemoveAll:
                xiph->removeAllPictures();
                break;
            case PictureOpType::RemoveByType: {
                auto pics = xiph->pictureList(); // copy
                for (auto* p : pics) {
                    if (p && static_cast<int>(p->type()) == op.type) {
                        xiph->removePicture(p, true);
                    }
                }
                break;
            }
            case PictureOpType::Add: {
                auto* pic = new TagLib::FLAC::Picture();
                pic->setType(static_cast<TagLib::FLAC::Picture::Type>(op.type));
                std::string mime = op.mimeType.empty() ? sniff_image_mime(op.data) : op.mimeType;
                pic->setMimeType(TagLib::String(mime, TagLib::String::UTF8));
                pic->setDescription(TagLib::String(op.description, TagLib::String::UTF8));
                pic->setData(op.data);
                xiph->addPicture(pic);
                break;
            }
        }
    }
    return 0;
}

static int apply_picture_ops_flac(TagLib::FLAC::File* flac,
                                  const std::vector<PictureOp>& ops) {
    if (!flac) return -5;
    for (const auto& op : ops) {
        switch (op.op) {
            case PictureOpType::RemoveAll:
                flac->removePictures();
                break;
            case PictureOpType::RemoveByType: {
                auto pics = flac->pictureList(); // copy
                for (auto* p : pics) {
                    if (p && static_cast<int>(p->type()) == op.type) {
                        flac->removePicture(p, true);
                    }
                }
                break;
            }
            case PictureOpType::Add: {
                auto* pic = new TagLib::FLAC::Picture();
                pic->setType(static_cast<TagLib::FLAC::Picture::Type>(op.type));
                std::string mime = op.mimeType.empty() ? sniff_image_mime(op.data) : op.mimeType;
                pic->setMimeType(TagLib::String(mime, TagLib::String::UTF8));
                pic->setDescription(TagLib::String(op.description, TagLib::String::UTF8));
                pic->setData(op.data);
                flac->addPicture(pic);
                break;
            }
        }
    }
    return 0;
}

static int apply_picture_ops_mp4(TagLib::MP4::File* mp4,
                                 const std::vector<PictureOp>& ops) {
    if (!mp4 || !mp4->tag()) return -5;
    auto* tag = mp4->tag();
    auto& items = tag->itemMap();

    TagLib::MP4::CoverArtList covers;
    auto it = items.find("covr");
    if (it != items.end()) covers = it->second.toCoverArtList();

    for (const auto& op : ops) {
        switch (op.op) {
            case PictureOpType::RemoveAll:
                covers.clear();
                break;
            case PictureOpType::RemoveByType:
                // MP4 covers don't have a type — interpret RemoveByType(frontCover)
                // and RemoveByType(other) as RemoveAll for sanity.
                if (op.type == 3 /*FrontCover*/ || op.type == 0 /*Other*/) {
                    covers.clear();
                }
                break;
            case PictureOpType::Add: {
                std::string mime = op.mimeType.empty() ? sniff_image_mime(op.data) : op.mimeType;
                covers.append(TagLib::MP4::CoverArt(mime_to_mp4_format(mime), op.data));
                break;
            }
        }
    }

    if (covers.isEmpty()) {
        tag->removeItem("covr");
    } else {
        tag->setItem("covr", TagLib::MP4::Item(covers));
    }
    return 0;
}

static int apply_picture_ops(TagLib::File* file, const std::vector<PictureOp>& ops) {
    if (ops.empty()) return 0;
    if (auto* mp3 = dynamic_cast<TagLib::MPEG::File*>(file)) {
        // Ensure ID3v2 tag exists.
        return apply_picture_ops_id3v2(mp3->ID3v2Tag(true), ops);
    }
    if (auto* flac = dynamic_cast<TagLib::FLAC::File*>(file)) {
        return apply_picture_ops_flac(flac, ops);
    }
    if (auto* mp4 = dynamic_cast<TagLib::MP4::File*>(file)) {
        return apply_picture_ops_mp4(mp4, ops);
    }
    if (auto* vorbis = dynamic_cast<TagLib::Ogg::Vorbis::File*>(file)) {
        return apply_picture_ops_xiph(vorbis->tag(), ops);
    }
    if (auto* opus = dynamic_cast<TagLib::Ogg::Opus::File*>(file)) {
        return apply_picture_ops_xiph(opus->tag(), ops);
    }
    if (auto* wav = dynamic_cast<TagLib::RIFF::WAV::File*>(file)) {
        return apply_picture_ops_id3v2(wav->ID3v2Tag(), ops);
    }
    if (auto* aiff = dynamic_cast<TagLib::RIFF::AIFF::File*>(file)) {
        return apply_picture_ops_id3v2(aiff->tag(), ops);
    }
    set_error("Picture write is not supported for this file format");
    return -5;
}

// ---------------------------------------------------------------------------
// Strip-other-tags handling per format.
// ---------------------------------------------------------------------------

static void strip_other_tags(TagLib::File* file) {
    if (!file) return;
    if (auto* mp3 = dynamic_cast<TagLib::MPEG::File*>(file)) {
        // Keep ID3v2 (canonical for MP3), drop ID3v1 and APE.
        mp3->strip(TagLib::MPEG::File::ID3v1 | TagLib::MPEG::File::APE);
        return;
    }
    if (auto* flac = dynamic_cast<TagLib::FLAC::File*>(file)) {
        // Keep XiphComment, drop ID3v1/ID3v2.
        flac->strip(TagLib::FLAC::File::ID3v1 | TagLib::FLAC::File::ID3v2);
        return;
    }
    if (auto* wav = dynamic_cast<TagLib::RIFF::WAV::File*>(file)) {
        // Keep ID3v2, drop INFO.
        wav->strip(TagLib::RIFF::WAV::File::Info);
        return;
    }
    // Other formats either have a single tag container or we don't have an
    // API to strip selectively — leave them alone.
}

// ---------------------------------------------------------------------------
// Reading: emit a JSON document.
// ---------------------------------------------------------------------------

static void emit_str_field(std::ostringstream& json, const TagLib::PropertyMap& pm,
                           const char* jsonKey, const char* propKey) {
    auto it = pm.find(propKey);
    if (it != pm.end() && !it->second.isEmpty()) {
        json << "\"" << jsonKey << "\":\""
             << json_escape(it->second.front().to8Bit(true)) << "\"";
    } else {
        json << "\"" << jsonKey << "\":null";
    }
}

static void emit_int_field(std::ostringstream& json, const TagLib::PropertyMap& pm,
                           const char* jsonKey, const char* propKey) {
    auto it = pm.find(propKey);
    if (it != pm.end() && !it->second.isEmpty()) {
        std::string raw = it->second.front().to8Bit(true);
        char* end = nullptr;
        long val = strtol(raw.c_str(), &end, 10);
        if (end != raw.c_str()) {
            json << "\"" << jsonKey << "\":" << val;
            return;
        }
    }
    json << "\"" << jsonKey << "\":null";
}

static void emit_split_field(std::ostringstream& json, const TagLib::PropertyMap& pm,
                             const char* numKey, const char* totalKey,
                             const char* numProp, const char* totalProp) {
    auto numIt = pm.find(numProp);
    auto totalIt = pm.find(totalProp);

    long num = -1, total = -1;
    bool hasNum = false, hasTotal = false;

    if (numIt != pm.end() && !numIt->second.isEmpty()) {
        std::string raw = numIt->second.front().to8Bit(true);
        auto slash = raw.find('/');
        if (slash != std::string::npos) {
            num = strtol(raw.c_str(), nullptr, 10);
            total = strtol(raw.c_str() + slash + 1, nullptr, 10);
            hasNum = true;
            hasTotal = true;
        } else {
            char* end = nullptr;
            long n = strtol(raw.c_str(), &end, 10);
            if (end != raw.c_str()) { num = n; hasNum = true; }
        }
    }
    if (!hasTotal && totalIt != pm.end() && !totalIt->second.isEmpty()) {
        char* end = nullptr;
        long t = strtol(totalIt->second.front().to8Bit(true).c_str(), &end, 10);
        if (end != totalIt->second.front().to8Bit(true).c_str()) {
            total = t; hasTotal = true;
        }
    }

    if (hasNum) json << "\"" << numKey << "\":" << num << ",";
    else        json << "\"" << numKey << "\":null,";
    if (hasTotal) json << "\"" << totalKey << "\":" << total;
    else          json << "\"" << totalKey << "\":null";
}

static int audio_bit_depth(TagLib::AudioProperties* props, TagLib::File* file) {
    if (!props) return 0;
    // TagLib's AudioProperties doesn't expose bitDepth uniformly — query via
    // dynamic_cast to format-specific subclasses where available.
    if (auto* flacProps = dynamic_cast<TagLib::FLAC::Properties*>(props)) return flacProps->bitsPerSample();
    if (auto* wavProps  = dynamic_cast<TagLib::RIFF::WAV::Properties*>(props)) return wavProps->bitsPerSample();
    if (auto* aiffProps = dynamic_cast<TagLib::RIFF::AIFF::Properties*>(props)) return aiffProps->bitsPerSample();
    if (auto* wvProps   = dynamic_cast<TagLib::WavPack::Properties*>(props)) return wvProps->bitsPerSample();
    if (auto* apeProps  = dynamic_cast<TagLib::APE::Properties*>(props)) return apeProps->bitsPerSample();
    if (auto* mp4Props  = dynamic_cast<TagLib::MP4::Properties*>(props)) return mp4Props->bitsPerSample();
    (void)file;
    return 0;
}

static void emit_picture(std::ostringstream& json, const PictureData& p) {
    json << "{";
    json << "\"type\":" << p.type;
    json << ",\"mimeType\":";
    if (!p.mimeType.empty()) json << "\"" << json_escape(p.mimeType) << "\"";
    else json << "null";
    json << ",\"description\":";
    if (!p.description.empty()) json << "\"" << json_escape(p.description) << "\"";
    else json << "null";
    json << ",\"data\":\""
         << base64_encode(reinterpret_cast<const unsigned char*>(p.data.data()), p.data.size())
         << "\"";
    json << "}";
}

static void emit_chapters_id3v2(std::ostringstream& json, TagLib::ID3v2::Tag* id3v2) {
    if (!id3v2) return;
    const auto& frameList = id3v2->frameList("CHAP");

    TagLib::ByteVectorList orderedIds;
    const auto& ctocFrames = id3v2->frameList("CTOC");
    for (const auto* ctocFrame : ctocFrames) {
        auto* ctoc = dynamic_cast<const TagLib::ID3v2::TableOfContentsFrame*>(ctocFrame);
        if (ctoc && ctoc->isTopLevel()) {
            orderedIds = ctoc->childElements();
            break;
        }
    }

    std::map<std::string, const TagLib::ID3v2::ChapterFrame*> chapMap;
    for (const auto* frame : frameList) {
        auto* chap = dynamic_cast<const TagLib::ID3v2::ChapterFrame*>(frame);
        if (chap) chapMap[std::string(chap->elementID().data(), chap->elementID().size())] = chap;
    }

    json << ",\"chapters\":[";
    bool firstChap = true;

    auto emitChapter = [&](const TagLib::ID3v2::ChapterFrame* chap) {
        if (!firstChap) json << ",";
        firstChap = false;

        unsigned int startOff = chap->startOffset();
        unsigned int endOff = chap->endOffset();

        json << "{";
        json << "\"elementId\":\""
             << json_escape(std::string(chap->elementID().data(), chap->elementID().size())) << "\",";
        json << "\"startTimeMs\":" << chap->startTime() << ",";
        json << "\"endTimeMs\":" << chap->endTime() << ",";
        json << "\"startOffset\":" << (startOff == 0xFFFFFFFFu ? -1 : (long)startOff) << ",";
        json << "\"endOffset\":"   << (endOff   == 0xFFFFFFFFu ? -1 : (long)endOff);

        const auto& tit2List = chap->embeddedFrameList("TIT2");
        if (!tit2List.isEmpty()) {
            auto* tit2 = dynamic_cast<const TagLib::ID3v2::TextIdentificationFrame*>(tit2List.front());
            if (tit2) {
                json << ",\"title\":\"" << json_escape(tit2->toString().to8Bit(true)) << "\"";
            }
        }

        json << "}";
    };

    if (!orderedIds.isEmpty()) {
        for (const auto& eid : orderedIds) {
            auto it = chapMap.find(std::string(eid.data(), eid.size()));
            if (it != chapMap.end()) emitChapter(it->second);
        }
    } else {
        for (const auto* frame : frameList) {
            auto* chap = dynamic_cast<const TagLib::ID3v2::ChapterFrame*>(frame);
            if (chap) emitChapter(chap);
        }
    }
    json << "]";
}

// ---------------------------------------------------------------------------
// Public C API
// ---------------------------------------------------------------------------

extern "C" {

const char* taglib_version(void) {
    return _TAGLIB_VERSION_STRING;
}

const char* taglib_last_error(void) {
    return t_last_error.c_str();
}

char* taglib_read_file(
    const char* path,
    int read_props,
    int read_pictures,
    int read_chapters,
    int read_raw_tags
) {
    clear_error();
    if (!path) { set_error("Null path"); return nullptr; }

    TagLib::FileRef file(path);
    if (file.isNull()) {
        set_error("Could not open or recognize file");
        return nullptr;
    }
    TagLib::Tag* tag = file.tag();
    if (!tag) {
        set_error("File has no readable tag");
        return nullptr;
    }

    std::ostringstream json;
    json << "{";

    TagLib::PropertyMap pm = file.properties();

    // ── Metadata ──────────────────────────────────────────────────────────
    json << "\"metadata\":{";
    emit_str_field(json, pm, "title",       "TITLE");        json << ",";
    emit_str_field(json, pm, "artist",      "ARTIST");       json << ",";
    emit_str_field(json, pm, "album",       "ALBUM");        json << ",";
    emit_str_field(json, pm, "albumArtist", "ALBUMARTIST");  json << ",";
    emit_str_field(json, pm, "genre",       "GENRE");        json << ",";
    emit_str_field(json, pm, "comment",     "COMMENT");      json << ",";
    emit_str_field(json, pm, "composer",    "COMPOSER");     json << ",";
    emit_str_field(json, pm, "lyricist",    "LYRICIST");     json << ",";
    emit_str_field(json, pm, "grouping",    "GROUPING");     json << ",";
    emit_int_field(json, pm, "year",        "DATE");         json << ",";
    emit_split_field(json, pm, "trackNumber", "trackTotal", "TRACKNUMBER", "TRACKTOTAL"); json << ",";
    emit_split_field(json, pm, "discNumber",  "discTotal",  "DISCNUMBER",  "DISCTOTAL");  json << ",";
    emit_str_field(json, pm, "lyrics",      "LYRICS");

    // Extras: any property-map keys not in the normalized set.
    json << ",\"extras\":{";
    bool firstExtra = true;
    for (auto it = pm.begin(); it != pm.end(); ++it) {
        std::string key = it->first.to8Bit(true);
        if (kReservedProperties.count(key)) continue;
        if (it->second.isEmpty()) continue;
        if (!firstExtra) json << ",";
        firstExtra = false;
        json << "\"" << json_escape(key) << "\":";
        if (it->second.size() == 1) {
            json << "\"" << json_escape(it->second.front().to8Bit(true)) << "\"";
        } else {
            json << "[";
            bool firstVal = true;
            for (const auto& val : it->second) {
                if (!firstVal) json << ",";
                firstVal = false;
                json << "\"" << json_escape(val.to8Bit(true)) << "\"";
            }
            json << "]";
        }
    }
    json << "}";

    json << "}"; // close metadata

    // ── Format / container ────────────────────────────────────────────────
    FileTypeInfo info = detect_file_type(file.file());
    json << ",\"format\":\"" << json_escape(info.format) << "\"";
    json << ",\"container\":\"" << json_escape(info.container) << "\"";

    // ── Audio properties ──────────────────────────────────────────────────
    if (read_props && file.audioProperties()) {
        TagLib::AudioProperties* props = file.audioProperties();
        json << ",\"properties\":{";
        json << "\"durationMs\":" << props->lengthInMilliseconds() << ",";
        json << "\"bitrate\":" << props->bitrate() << ",";
        json << "\"sampleRate\":" << props->sampleRate() << ",";
        json << "\"channels\":" << props->channels() << ",";
        int bits = audio_bit_depth(props, file.file());
        if (bits > 0) json << "\"bitDepth\":" << bits;
        else          json << "\"bitDepth\":null";
        json << "}";
    }

    // ── Pictures ──────────────────────────────────────────────────────────
    if (read_pictures) {
        auto pics = extract_pictures(file.file());
        json << ",\"pictures\":[";
        for (size_t i = 0; i < pics.size(); ++i) {
            if (i) json << ",";
            emit_picture(json, pics[i]);
        }
        json << "]";
    }

    // ── Chapters (ID3v2 only) ─────────────────────────────────────────────
    if (read_chapters) {
        auto* mpegFile = dynamic_cast<TagLib::MPEG::File*>(file.file());
        if (mpegFile && mpegFile->hasID3v2Tag()) {
            emit_chapters_id3v2(json, mpegFile->ID3v2Tag());
        }
    }

    // ── Raw tags (full property map) ──────────────────────────────────────
    if (read_raw_tags) {
        json << ",\"rawTags\":[{\"tagType\":\"properties\",\"fields\":{";
        bool first = true;
        for (auto it = pm.begin(); it != pm.end(); ++it) {
            if (!first) json << ",";
            first = false;
            json << "\"" << json_escape(it->first.to8Bit(true)) << "\":[";
            bool firstVal = true;
            for (const auto& val : it->second) {
                if (!firstVal) json << ",";
                firstVal = false;
                json << "\"" << json_escape(val.to8Bit(true)) << "\"";
            }
            json << "]";
        }
        json << "}}]";
    }

    json << "}";
    return to_heap_string(json.str());
}

int taglib_write_file(const char* path, const char* patch_json) {
    clear_error();
    if (!path) { set_error("Null path"); return -1; }
    if (!patch_json) { set_error("Null patch"); return -3; }

    TagLib::FileRef file(path);
    if (file.isNull()) {
        set_error("Could not open or recognize file");
        return -1;
    }
    if (!file.tag()) {
        set_error("File has no writable tag");
        return -2;
    }

    JParser parser(patch_json);
    JValue root = parser.parse();
    if (!parser.good() || root.type != JValue::Object) {
        set_error("Invalid patch JSON");
        return -3;
    }

    TagLib::PropertyMap pm = file.properties();

    // -- Apply set fields ----------------------------------------------------
    auto sf = root.obj.find("setFields");
    if (sf != root.obj.end() && sf->second.type == JValue::Object) {
        for (auto& kv : sf->second.obj) {
            const char* prop = json_to_property(kv.first);
            if (!prop) continue;
            const TagLib::String key(prop);

            if (kv.second.type == JValue::String) {
                pm.replace(key, TagLib::StringList(
                    TagLib::String(kv.second.str, TagLib::String::UTF8)));
            } else if (kv.second.type == JValue::Number) {
                std::ostringstream ss;
                ss << static_cast<long long>(kv.second.num);
                pm.replace(key, TagLib::StringList(TagLib::String(ss.str())));
            } else if (kv.second.type == JValue::Array) {
                TagLib::StringList list;
                for (const auto& v : kv.second.arr) {
                    if (v.type == JValue::String) {
                        list.append(TagLib::String(v.str, TagLib::String::UTF8));
                    } else if (v.type == JValue::Number) {
                        std::ostringstream ss; ss << static_cast<long long>(v.num);
                        list.append(TagLib::String(ss.str()));
                    }
                }
                pm.replace(key, list);
            } else if (kv.second.type == JValue::Null) {
                pm.erase(key);
            }
        }
    }

    // -- Apply clear fields --------------------------------------------------
    auto cf = root.obj.find("clearFields");
    if (cf != root.obj.end() && cf->second.type == JValue::Array) {
        for (auto& item : cf->second.arr) {
            if (item.type != JValue::String) continue;
            const char* prop = json_to_property(item.str);
            if (!prop) continue;
            pm.erase(TagLib::String(prop));
        }
    }

    // -- Apply raw mutations ------------------------------------------------
    auto rm = root.obj.find("rawMutations");
    if (rm != root.obj.end() && rm->second.type == JValue::Object) {
        for (auto& kv : rm->second.obj) {
            const TagLib::String key(kv.first, TagLib::String::UTF8);
            if (kv.second.type == JValue::String) {
                pm.replace(key, TagLib::StringList(
                    TagLib::String(kv.second.str, TagLib::String::UTF8)));
            } else if (kv.second.type == JValue::Number) {
                std::ostringstream ss; ss << static_cast<long long>(kv.second.num);
                pm.replace(key, TagLib::StringList(TagLib::String(ss.str())));
            } else if (kv.second.type == JValue::Array) {
                TagLib::StringList list;
                for (const auto& v : kv.second.arr) {
                    if (v.type == JValue::String) {
                        list.append(TagLib::String(v.str, TagLib::String::UTF8));
                    } else if (v.type == JValue::Number) {
                        std::ostringstream ss; ss << static_cast<long long>(v.num);
                        list.append(TagLib::String(ss.str()));
                    }
                }
                pm.replace(key, list);
            } else if (kv.second.type == JValue::Null) {
                pm.erase(key);
            }
        }
    }

    // ID3v2 stores N/T combined under TRACKNUMBER. When both trackNumber and
    // trackTotal are present in the property map, fold the total into the
    // number so it round-trips correctly. PropertyMap → ID3v2 in TagLib emits
    // TRACKTOTAL as a TXXX frame, which loses the total on common readers.
    bool isId3v2Container = false;
    if (auto* mp3 = dynamic_cast<TagLib::MPEG::File*>(file.file())) {
        isId3v2Container = mp3->hasID3v2Tag() || true; // ID3v2 will be created on save
    } else if (auto* wav = dynamic_cast<TagLib::RIFF::WAV::File*>(file.file())) {
        isId3v2Container = wav->hasID3v2Tag();
    } else if (auto* aiff = dynamic_cast<TagLib::RIFF::AIFF::File*>(file.file())) {
        isId3v2Container = aiff->hasID3v2Tag();
    }
    if (isId3v2Container) {
        auto fold = [&](const char* numKey, const char* totalKey) {
            auto numIt = pm.find(numKey);
            auto totIt = pm.find(totalKey);
            if (numIt != pm.end() && !numIt->second.isEmpty() &&
                totIt != pm.end() && !totIt->second.isEmpty()) {
                std::string n = numIt->second.front().to8Bit(true);
                std::string t = totIt->second.front().to8Bit(true);
                // Skip if numeric portion already contains a slash.
                if (n.find('/') == std::string::npos) {
                    pm.replace(TagLib::String(numKey),
                               TagLib::StringList(TagLib::String(n + "/" + t)));
                    pm.erase(TagLib::String(totalKey));
                }
            }
        };
        fold("TRACKNUMBER", "TRACKTOTAL");
        fold("DISCNUMBER", "DISCTOTAL");
    }

    file.setProperties(pm);

    // -- Apply picture operations -------------------------------------------
    auto po = root.obj.find("pictureOperations");
    if (po != root.obj.end() && po->second.type == JValue::Array && !po->second.arr.empty()) {
        std::vector<PictureOp> ops;
        ops.reserve(po->second.arr.size());
        for (const auto& opJson : po->second.arr) {
            if (opJson.type != JValue::Object) continue;
            auto oit = opJson.obj.find("op");
            if (oit == opJson.obj.end() || oit->second.type != JValue::String) continue;
            const std::string& opName = oit->second.str;
            PictureOp op;
            if (opName == "removeAll") {
                op.op = PictureOpType::RemoveAll;
            } else if (opName == "removeByType") {
                op.op = PictureOpType::RemoveByType;
                auto tit = opJson.obj.find("type");
                if (tit != opJson.obj.end() && tit->second.type == JValue::Number) {
                    op.type = static_cast<int>(tit->second.num);
                }
            } else if (opName == "add") {
                op.op = PictureOpType::Add;
                auto pit = opJson.obj.find("picture");
                if (pit == opJson.obj.end() || pit->second.type != JValue::Object) continue;
                const auto& po_obj = pit->second.obj;
                auto t = po_obj.find("type");
                auto m = po_obj.find("mimeType");
                auto d = po_obj.find("description");
                auto da = po_obj.find("data");
                if (t != po_obj.end() && t->second.type == JValue::Number) op.type = static_cast<int>(t->second.num);
                if (m != po_obj.end() && m->second.type == JValue::String) op.mimeType = m->second.str;
                if (d != po_obj.end() && d->second.type == JValue::String) op.description = d->second.str;
                if (da != po_obj.end() && da->second.type == JValue::String) {
                    auto bytes = base64_decode(da->second.str);
                    op.data = TagLib::ByteVector(reinterpret_cast<const char*>(bytes.data()),
                                                 static_cast<unsigned int>(bytes.size()));
                }
            } else {
                continue;
            }
            ops.push_back(std::move(op));
        }
        int rc = apply_picture_ops(file.file(), ops);
        if (rc != 0) return rc;
    }

    // -- Strip other tags ---------------------------------------------------
    auto so = root.obj.find("stripOtherTags");
    if (so != root.obj.end() && so->second.type == JValue::Bool && so->second.flag) {
        strip_other_tags(file.file());
    }

    if (!file.save()) {
        set_error("Failed to save file");
        return -4;
    }
    return 0;
}

void taglib_free_string(char* str) {
    free(str);
}

} // extern "C"
