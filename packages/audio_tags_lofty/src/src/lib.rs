// lofty_shim
//
// C ABI shim around the Lofty crate for the audio_tags_lofty Dart package.
// The shim mirrors the JSON protocol used by the TagLib backend so the two
// can be used interchangeably from Dart.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

use lofty::config::{ParseOptions, WriteOptions};
use lofty::file::{FileType, TaggedFileExt};
use lofty::picture::{MimeType, Picture, PictureType};
use lofty::prelude::*;
use lofty::probe::Probe;
use lofty::tag::{ItemKey, ItemValue, Tag, TagItem, TagType};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Per-thread last-error storage.
// ---------------------------------------------------------------------------

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::new("").unwrap());
}

fn set_error(msg: impl Into<String>) {
    let s = CString::new(msg.into()).unwrap_or_else(|_| CString::new("").unwrap());
    LAST_ERROR.with(|cell| *cell.borrow_mut() = s);
}

fn clear_error() {
    LAST_ERROR.with(|cell| *cell.borrow_mut() = CString::new("").unwrap());
}

// ---------------------------------------------------------------------------
// JSON response types — mirror the TagLib shim protocol exactly.
// ---------------------------------------------------------------------------

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ReadResponse {
    metadata: Metadata,
    #[serde(skip_serializing_if = "Option::is_none")]
    format: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    container: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    properties: Option<Properties>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pictures: Vec<JsonPicture>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    raw_tags: Vec<RawTag>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Metadata {
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    album_artist: Option<String>,
    genre: Option<String>,
    comment: Option<String>,
    composer: Option<String>,
    lyricist: Option<String>,
    grouping: Option<String>,
    year: Option<u32>,
    track_number: Option<u32>,
    track_total: Option<u32>,
    disc_number: Option<u32>,
    disc_total: Option<u32>,
    lyrics: Option<String>,
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    extras: HashMap<String, serde_json::Value>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Properties {
    duration_ms: u64,
    bitrate: Option<u32>,
    sample_rate: Option<u32>,
    channels: Option<u8>,
    bit_depth: Option<u8>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct JsonPicture {
    r#type: u8,
    mime_type: Option<String>,
    description: Option<String>,
    data: String, // base64-encoded
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RawTag {
    tag_type: String,
    fields: HashMap<String, Vec<String>>,
}

// ---------------------------------------------------------------------------
// JSON patch types for write.
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WritePatch {
    #[serde(default)]
    set_fields: HashMap<String, serde_json::Value>,
    #[serde(default)]
    clear_fields: Vec<String>,
    #[serde(default)]
    raw_mutations: HashMap<String, serde_json::Value>,
    #[serde(default)]
    picture_operations: Vec<serde_json::Value>,
    #[serde(default)]
    strip_other_tags: bool,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn lofty_version_string() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

fn tag_type_name(tag_type: TagType) -> &'static str {
    match tag_type {
        TagType::Id3v1 => "ID3v1",
        TagType::Id3v2 => "ID3v2",
        TagType::Mp4Ilst => "MP4",
        TagType::VorbisComments => "VorbisComments",
        TagType::RiffInfo => "RIFF-INFO",
        TagType::Ape => "APE",
        TagType::AiffText => "AIFFText",
        _ => "unknown",
    }
}

fn file_type_name(ft: FileType) -> &'static str {
    match ft {
        FileType::Aac => "aac",
        FileType::Aiff => "aiff",
        FileType::Ape => "ape",
        FileType::Flac => "flac",
        FileType::Mpeg => "mp3",
        FileType::Mp4 => "mp4",
        FileType::Mpc => "mpc",
        FileType::Opus => "opus",
        FileType::Vorbis => "ogg-vorbis",
        FileType::Speex => "speex",
        FileType::Wav => "wav",
        FileType::WavPack => "wv",
        _ => "unknown",
    }
}

/// Extract a 4-digit year from a string. Tolerant of ISO dates ("2024-03-15"),
/// 2-digit years ("99"), and trailing junk.
fn parse_year(s: &str) -> Option<u32> {
    let digits: String = s.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return None;
    }
    if digits.len() >= 4 {
        digits[..4].parse().ok()
    } else {
        digits.parse().ok()
    }
}

fn parse_u32(s: &str) -> Option<u32> {
    let digits: String = s.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return None;
    }
    digits.parse().ok()
}

/// Map a `TagItem` key to the canonical Vorbis/PropertyMap key string used by
/// the TagLib backend. Keeps the cross-backend raw-tag protocol consistent.
///
/// Falls back to lofty's VorbisComments format key (and finally to the Debug
/// representation upper-cased) so that arbitrary keys still surface with a
/// stable name.
fn property_name_for(key: ItemKey) -> String {
    match key {
        ItemKey::TrackTitle => "TITLE".into(),
        ItemKey::TrackArtist => "ARTIST".into(),
        ItemKey::AlbumTitle => "ALBUM".into(),
        ItemKey::AlbumArtist => "ALBUMARTIST".into(),
        ItemKey::Genre => "GENRE".into(),
        ItemKey::Comment => "COMMENT".into(),
        ItemKey::Composer => "COMPOSER".into(),
        ItemKey::Lyricist => "LYRICIST".into(),
        ItemKey::ContentGroup => "GROUPING".into(),
        ItemKey::Year => "DATE".into(),
        ItemKey::ReleaseDate => "DATE".into(),
        ItemKey::TrackNumber => "TRACKNUMBER".into(),
        ItemKey::TrackTotal => "TRACKTOTAL".into(),
        ItemKey::DiscNumber => "DISCNUMBER".into(),
        ItemKey::DiscTotal => "DISCTOTAL".into(),
        ItemKey::Lyrics => "LYRICS".into(),
        ItemKey::Isrc => "ISRC".into(),
        ItemKey::Bpm => "BPM".into(),
        ItemKey::CopyrightMessage => "COPYRIGHT".into(),
        ItemKey::EncodedBy => "ENCODEDBY".into(),
        ItemKey::EncoderSoftware => "ENCODER".into(),
        ItemKey::Mood => "MOOD".into(),
        ItemKey::Language => "LANGUAGE".into(),
        ItemKey::Publisher => "PUBLISHER".into(),
        ItemKey::Label => "LABEL".into(),
        ItemKey::CatalogNumber => "CATALOGNUMBER".into(),
        ItemKey::Performer => "PERFORMER".into(),
        ItemKey::Conductor => "CONDUCTOR".into(),
        ItemKey::Director => "DIRECTOR".into(),
        ItemKey::Remixer => "REMIXER".into(),
        ItemKey::Engineer => "ENGINEER".into(),
        ItemKey::Producer => "PRODUCER".into(),
        ItemKey::MixEngineer => "MIXER".into(),
        ItemKey::OriginalArtist => "ORIGINALARTIST".into(),
        ItemKey::OriginalAlbumTitle => "ORIGINALALBUM".into(),
        ItemKey::OriginalReleaseDate => "ORIGINALDATE".into(),
        ItemKey::Writer => "WRITER".into(),
        ItemKey::MusicianCredits => "MUSICIANCREDITS".into(),
        ItemKey::ReplayGainAlbumGain => "REPLAYGAIN_ALBUM_GAIN".into(),
        ItemKey::ReplayGainAlbumPeak => "REPLAYGAIN_ALBUM_PEAK".into(),
        ItemKey::ReplayGainTrackGain => "REPLAYGAIN_TRACK_GAIN".into(),
        ItemKey::ReplayGainTrackPeak => "REPLAYGAIN_TRACK_PEAK".into(),
        ItemKey::MusicBrainzRecordingId => "MUSICBRAINZ_TRACKID".into(),
        ItemKey::MusicBrainzReleaseId => "MUSICBRAINZ_ALBUMID".into(),
        ItemKey::MusicBrainzArtistId => "MUSICBRAINZ_ARTISTID".into(),
        ItemKey::MusicBrainzReleaseArtistId => "MUSICBRAINZ_ALBUMARTISTID".into(),
        ItemKey::MusicBrainzReleaseGroupId => "MUSICBRAINZ_RELEASEGROUPID".into(),
        ItemKey::MusicBrainzWorkId => "MUSICBRAINZ_WORKID".into(),
        other => other
            .map_key(TagType::VorbisComments)
            .map(|s| s.to_string())
            .unwrap_or_else(|| format!("{:?}", other).to_uppercase()),
    }
}

/// Reserved property keys that map to normalized fields and therefore should
/// be excluded from the `extras` map.
fn is_reserved_property(name: &str) -> bool {
    matches!(
        name,
        "TITLE"
            | "ARTIST"
            | "ALBUM"
            | "ALBUMARTIST"
            | "GENRE"
            | "COMMENT"
            | "COMPOSER"
            | "LYRICIST"
            | "GROUPING"
            | "DATE"
            | "TRACKNUMBER"
            | "TRACKTOTAL"
            | "DISCNUMBER"
            | "DISCTOTAL"
            | "LYRICS"
    )
}

/// Map a property-map name to a lofty `ItemKey` if one is defined for that
/// name. Returns `None` for keys lofty doesn't model — those callers should
/// log/skip rather than try to write through.
fn item_key_for_property(name: &str) -> Option<ItemKey> {
    Some(match name {
        "TITLE" => ItemKey::TrackTitle,
        "ARTIST" => ItemKey::TrackArtist,
        "ALBUM" => ItemKey::AlbumTitle,
        "ALBUMARTIST" => ItemKey::AlbumArtist,
        "GENRE" => ItemKey::Genre,
        "COMMENT" => ItemKey::Comment,
        "COMPOSER" => ItemKey::Composer,
        "LYRICIST" => ItemKey::Lyricist,
        "GROUPING" => ItemKey::ContentGroup,
        // RecordingDate maps to ID3v2 TDRC, Vorbis DATE, and MP4 ©day —
        // covering all formats we write. ItemKey::Year has no ID3v2 mapping.
        "DATE" => ItemKey::RecordingDate,
        "TRACKNUMBER" => ItemKey::TrackNumber,
        "TRACKTOTAL" => ItemKey::TrackTotal,
        "DISCNUMBER" => ItemKey::DiscNumber,
        "DISCTOTAL" => ItemKey::DiscTotal,
        // ItemKey::Lyrics is *not* mapped for ID3v2; UnsyncLyrics writes to
        // USLT and is also valid for MP4 and Vorbis.
        "LYRICS" => ItemKey::UnsyncLyrics,
        "ISRC" => ItemKey::Isrc,
        "BPM" => ItemKey::Bpm,
        "COPYRIGHT" => ItemKey::CopyrightMessage,
        "ENCODEDBY" => ItemKey::EncodedBy,
        "ENCODER" => ItemKey::EncoderSoftware,
        "MOOD" => ItemKey::Mood,
        "LANGUAGE" => ItemKey::Language,
        "PUBLISHER" => ItemKey::Publisher,
        "LABEL" => ItemKey::Label,
        "CATALOGNUMBER" => ItemKey::CatalogNumber,
        "PERFORMER" => ItemKey::Performer,
        "CONDUCTOR" => ItemKey::Conductor,
        "MUSICBRAINZ_TRACKID" => ItemKey::MusicBrainzRecordingId,
        "MUSICBRAINZ_ALBUMID" => ItemKey::MusicBrainzReleaseId,
        "MUSICBRAINZ_ARTISTID" => ItemKey::MusicBrainzArtistId,
        "MUSICBRAINZ_ALBUMARTISTID" => ItemKey::MusicBrainzReleaseArtistId,
        "MUSICBRAINZ_RELEASEGROUPID" => ItemKey::MusicBrainzReleaseGroupId,
        "MUSICBRAINZ_WORKID" => ItemKey::MusicBrainzWorkId,
        "REPLAYGAIN_ALBUM_GAIN" => ItemKey::ReplayGainAlbumGain,
        "REPLAYGAIN_ALBUM_PEAK" => ItemKey::ReplayGainAlbumPeak,
        "REPLAYGAIN_TRACK_GAIN" => ItemKey::ReplayGainTrackGain,
        "REPLAYGAIN_TRACK_PEAK" => ItemKey::ReplayGainTrackPeak,
        _ => return None,
    })
}

fn json_field_to_property(name: &str) -> Option<&'static str> {
    Some(match name {
        "title" => "TITLE",
        "artist" => "ARTIST",
        "album" => "ALBUM",
        "albumArtist" => "ALBUMARTIST",
        "genre" => "GENRE",
        "comment" => "COMMENT",
        "composer" => "COMPOSER",
        "lyricist" => "LYRICIST",
        "grouping" => "GROUPING",
        "year" => "DATE",
        "trackNumber" => "TRACKNUMBER",
        "trackTotal" => "TRACKTOTAL",
        "discNumber" => "DISCNUMBER",
        "discTotal" => "DISCTOTAL",
        "lyrics" => "LYRICS",
        _ => return None,
    })
}

fn pic_type_to_index(t: PictureType) -> u8 {
    match t {
        PictureType::Other => 0,
        PictureType::Icon => 1,
        PictureType::OtherIcon => 2,
        PictureType::CoverFront => 3,
        PictureType::CoverBack => 4,
        PictureType::Leaflet => 5,
        PictureType::Media => 6,
        PictureType::LeadArtist => 7,
        PictureType::Artist => 8,
        PictureType::Conductor => 9,
        PictureType::Band => 10,
        PictureType::Composer => 11,
        PictureType::Lyricist => 12,
        PictureType::RecordingLocation => 13,
        PictureType::DuringRecording => 14,
        PictureType::DuringPerformance => 15,
        PictureType::ScreenCapture => 16,
        PictureType::BrightFish => 17,
        PictureType::Illustration => 18,
        PictureType::BandLogo => 19,
        PictureType::PublisherLogo => 20,
        _ => 0,
    }
}

fn index_to_pic_type(i: u8) -> PictureType {
    match i {
        0 => PictureType::Other,
        1 => PictureType::Icon,
        2 => PictureType::OtherIcon,
        3 => PictureType::CoverFront,
        4 => PictureType::CoverBack,
        5 => PictureType::Leaflet,
        6 => PictureType::Media,
        7 => PictureType::LeadArtist,
        8 => PictureType::Artist,
        9 => PictureType::Conductor,
        10 => PictureType::Band,
        11 => PictureType::Composer,
        12 => PictureType::Lyricist,
        13 => PictureType::RecordingLocation,
        14 => PictureType::DuringRecording,
        15 => PictureType::DuringPerformance,
        16 => PictureType::ScreenCapture,
        17 => PictureType::BrightFish,
        18 => PictureType::Illustration,
        19 => PictureType::BandLogo,
        20 => PictureType::PublisherLogo,
        _ => PictureType::Other,
    }
}

fn mime_from_str(mime: &str) -> MimeType {
    match mime.to_ascii_lowercase().as_str() {
        "image/jpeg" | "image/jpg" => MimeType::Jpeg,
        "image/png" => MimeType::Png,
        "image/gif" => MimeType::Gif,
        "image/bmp" => MimeType::Bmp,
        "image/tiff" => MimeType::Tiff,
        other => MimeType::Unknown(other.to_string()),
    }
}

fn mime_to_str(mime: &MimeType) -> String {
    match mime {
        MimeType::Jpeg => "image/jpeg".into(),
        MimeType::Png => "image/png".into(),
        MimeType::Gif => "image/gif".into(),
        MimeType::Bmp => "image/bmp".into(),
        MimeType::Tiff => "image/tiff".into(),
        MimeType::Unknown(s) => s.clone(),
        _ => "application/octet-stream".into(),
    }
}

/// Sniff a MIME type from raw image bytes.
fn sniff_image_mime(data: &[u8]) -> &'static str {
    if data.len() >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
        return "image/jpeg";
    }
    if data.len() >= 8
        && data[0] == 0x89
        && data[1] == b'P'
        && data[2] == b'N'
        && data[3] == b'G'
    {
        return "image/png";
    }
    if data.len() >= 6 && data[0] == b'G' && data[1] == b'I' && data[2] == b'F' {
        return "image/gif";
    }
    if data.len() >= 2 && data[0] == b'B' && data[1] == b'M' {
        return "image/bmp";
    }
    "application/octet-stream"
}

// Base64 encode/decode (no extra dependency).

const B64_CHARS: &[u8] =
    b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64_encode(data: &[u8]) -> String {
    let mut result = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let n = (b0 << 16) | (b1 << 8) | b2;
        result.push(B64_CHARS[((n >> 18) & 63) as usize] as char);
        result.push(B64_CHARS[((n >> 12) & 63) as usize] as char);
        result.push(if chunk.len() > 1 {
            B64_CHARS[((n >> 6) & 63) as usize] as char
        } else {
            '='
        });
        result.push(if chunk.len() > 2 {
            B64_CHARS[(n & 63) as usize] as char
        } else {
            '='
        });
    }
    result
}

fn base64_decode(input: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(input.len() * 3 / 4);
    let mut buf: u32 = 0;
    let mut bits: u32 = 0;
    for c in input.chars() {
        let v = match c {
            'A'..='Z' => c as u32 - b'A' as u32,
            'a'..='z' => c as u32 - b'a' as u32 + 26,
            '0'..='9' => c as u32 - b'0' as u32 + 52,
            '+' => 62,
            '/' => 63,
            '=' => break,
            _ => continue,
        };
        buf = (buf << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xFF) as u8);
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Read-side extraction.
// ---------------------------------------------------------------------------

fn extract_metadata(tag: &Tag) -> Metadata {
    // ItemKey::Year only maps for Vorbis ("YEAR") and APE; ID3v2 stores year
    // in TDRC (RecordingDate) and Vorbis often uses DATE (RecordingDate too).
    // Try RecordingDate first to cover ID3v2, then fall back.
    let year = tag
        .get_string(ItemKey::RecordingDate)
        .or_else(|| tag.get_string(ItemKey::Year))
        .or_else(|| tag.get_string(ItemKey::ReleaseDate))
        .and_then(parse_year);

    // Track / disc fall back to "N/T" parsing when the convenience accessor
    // returns None (some files store combined values under TRACKNUMBER).
    let mut track_number = tag.track();
    let mut track_total = tag.track_total();
    if track_number.is_none() {
        track_number = tag.get_string(ItemKey::TrackNumber).and_then(parse_u32);
    }
    if track_total.is_none() {
        if let Some(s) = tag.get_string(ItemKey::TrackNumber) {
            if let Some(slash) = s.find('/') {
                track_total = parse_u32(&s[slash + 1..]);
            }
        }
        if track_total.is_none() {
            track_total = tag.get_string(ItemKey::TrackTotal).and_then(parse_u32);
        }
    }
    let mut disc_number = tag.disk();
    let mut disc_total = tag.disk_total();
    if disc_number.is_none() {
        disc_number = tag.get_string(ItemKey::DiscNumber).and_then(parse_u32);
    }
    if disc_total.is_none() {
        if let Some(s) = tag.get_string(ItemKey::DiscNumber) {
            if let Some(slash) = s.find('/') {
                disc_total = parse_u32(&s[slash + 1..]);
            }
        }
        if disc_total.is_none() {
            disc_total = tag.get_string(ItemKey::DiscTotal).and_then(parse_u32);
        }
    }

    // Extras: any text item not covered by the normalized fields.
    let mut extras: HashMap<String, serde_json::Value> = HashMap::new();
    for item in tag.items() {
        let prop = property_name_for(item.key());
        if is_reserved_property(&prop) {
            continue;
        }
        if let ItemValue::Text(text) = item.value() {
            match extras.get_mut(&prop) {
                Some(serde_json::Value::Array(arr)) => {
                    arr.push(serde_json::Value::String(text.to_string()));
                }
                Some(existing) => {
                    let prev = existing.clone();
                    *existing = serde_json::Value::Array(vec![
                        prev,
                        serde_json::Value::String(text.to_string()),
                    ]);
                }
                None => {
                    extras.insert(prop, serde_json::Value::String(text.to_string()));
                }
            }
        }
    }

    Metadata {
        title: tag.title().map(|s| s.to_string()),
        artist: tag.artist().map(|s| s.to_string()),
        album: tag.album().map(|s| s.to_string()),
        album_artist: tag.get_string(ItemKey::AlbumArtist).map(|s| s.to_string()),
        genre: tag.genre().map(|s| s.to_string()),
        comment: tag.comment().map(|s| s.to_string()),
        composer: tag.get_string(ItemKey::Composer).map(|s| s.to_string()),
        lyricist: tag.get_string(ItemKey::Lyricist).map(|s| s.to_string()),
        grouping: tag
            .get_string(ItemKey::ContentGroup)
            .map(|s| s.to_string()),
        year,
        track_number,
        track_total,
        disc_number,
        disc_total,
        lyrics: tag
            .get_string(ItemKey::UnsyncLyrics)
            .or_else(|| tag.get_string(ItemKey::Lyrics))
            .map(|s| s.to_string()),
        extras,
    }
}

fn extract_pictures(tag: &Tag) -> Vec<JsonPicture> {
    tag.pictures()
        .iter()
        .map(|pic| {
            let mime = pic
                .mime_type()
                .map(mime_to_str)
                .unwrap_or_else(|| sniff_image_mime(pic.data()).to_string());
            JsonPicture {
                r#type: pic_type_to_index(pic.pic_type()),
                mime_type: Some(mime),
                description: pic.description().map(|d| d.to_string()),
                data: base64_encode(pic.data()),
            }
        })
        .collect()
}

fn extract_raw_tags(tagged_file: &lofty::file::TaggedFile) -> Vec<RawTag> {
    tagged_file
        .tags()
        .iter()
        .map(|tag| {
            let mut fields: HashMap<String, Vec<String>> = HashMap::new();
            for item in tag.items() {
                if let ItemValue::Text(text) = item.value() {
                    let key = property_name_for(item.key());
                    fields.entry(key).or_default().push(text.to_string());
                }
            }
            RawTag {
                tag_type: tag_type_name(tag.tag_type()).to_string(),
                fields,
            }
        })
        .collect()
}

fn to_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

// ---------------------------------------------------------------------------
// Write-side helpers.
// ---------------------------------------------------------------------------

fn apply_set_value(tag: &mut Tag, key: ItemKey, value: &serde_json::Value) {
    match value {
        serde_json::Value::Null => {
            tag.remove_key(key);
        }
        serde_json::Value::String(s) => {
            tag.insert_text(key, s.clone());
        }
        serde_json::Value::Number(n) => {
            tag.insert_text(key, n.to_string());
        }
        serde_json::Value::Bool(b) => {
            tag.insert_text(key, b.to_string());
        }
        serde_json::Value::Array(arr) => {
            tag.remove_key(key);
            for v in arr {
                let s = match v {
                    serde_json::Value::String(s) => s.clone(),
                    serde_json::Value::Number(n) => n.to_string(),
                    serde_json::Value::Bool(b) => b.to_string(),
                    _ => continue,
                };
                let item = TagItem::new(key, ItemValue::Text(s));
                tag.push(item);
            }
        }
        _ => {}
    }
}

/// Replace the entire picture list. Lofty doesn't expose a single
/// `set_pictures` call, so we remove from the end (avoids index shifting)
/// and then push the replacements.
fn replace_all_pictures(tag: &mut Tag, new_pictures: Vec<Picture>) {
    while !tag.pictures().is_empty() {
        let last = tag.pictures().len() - 1;
        tag.remove_picture(last);
    }
    for pic in new_pictures {
        tag.push_picture(pic);
    }
}

fn apply_picture_op(tag: &mut Tag, op: &serde_json::Value) -> Result<(), String> {
    let op_obj = op.as_object().ok_or("picture op must be an object")?;
    let op_name = op_obj
        .get("op")
        .and_then(|v| v.as_str())
        .ok_or("picture op missing 'op' field")?;
    match op_name {
        "removeAll" => {
            replace_all_pictures(tag, Vec::new());
            Ok(())
        }
        "removeByType" => {
            let target =
                op_obj.get("type").and_then(|v| v.as_u64()).unwrap_or(0) as u8;
            let target_pt = index_to_pic_type(target);
            tag.remove_picture_type(target_pt);
            Ok(())
        }
        "add" => {
            let pic_obj = op_obj
                .get("picture")
                .and_then(|v| v.as_object())
                .ok_or("add op missing 'picture' object")?;
            let pic_type_idx =
                pic_obj.get("type").and_then(|v| v.as_u64()).unwrap_or(0) as u8;
            let mime_str = pic_obj
                .get("mimeType")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let description = pic_obj
                .get("description")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let data_b64 = pic_obj
                .get("data")
                .and_then(|v| v.as_str())
                .ok_or("add op missing 'data'")?;
            let data = base64_decode(data_b64);
            let mime = match mime_str {
                Some(s) if !s.is_empty() => mime_from_str(&s),
                _ => mime_from_str(sniff_image_mime(&data)),
            };
            let pic_type = index_to_pic_type(pic_type_idx);

            let mut builder = Picture::unchecked(data).pic_type(pic_type).mime_type(mime);
            if let Some(d) = description {
                builder = builder.description(d);
            }
            let pic = builder.build();

            // Replace existing pictures of the same role to avoid duplicates,
            // then add this one.
            tag.remove_picture_type(pic_type);
            tag.push_picture(pic);
            Ok(())
        }
        other => Err(format!("unknown picture op: {}", other)),
    }
}

// Lofty handles ID3v2 TRCK/TPOS combination natively when converting from a
// generic `Tag` to an `Id3v2Tag`, so no manual fold is needed.

// ---------------------------------------------------------------------------
// Public C API
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn lofty_version() -> *const c_char {
    use std::sync::OnceLock;
    static VERSION: OnceLock<CString> = OnceLock::new();
    VERSION
        .get_or_init(|| CString::new(lofty_version_string()).unwrap())
        .as_ptr()
}

#[no_mangle]
pub extern "C" fn lofty_last_error() -> *const c_char {
    LAST_ERROR.with(|cell| cell.borrow().as_ptr())
}

#[no_mangle]
pub extern "C" fn lofty_read_file(
    path: *const c_char,
    read_props: i32,
    read_pictures: i32,
    _read_chapters: i32, // Lofty does not support chapters.
    read_raw_tags: i32,
) -> *mut c_char {
    clear_error();
    if path.is_null() {
        set_error("Null path");
        return std::ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Path is not valid UTF-8");
            return std::ptr::null_mut();
        }
    };

    let tagged_file = match Probe::open(Path::new(path_str))
        .and_then(|probe| probe.options(ParseOptions::new()).read())
    {
        Ok(f) => f,
        Err(e) => {
            set_error(format!("Could not open or recognize file: {}", e));
            return std::ptr::null_mut();
        }
    };

    let format = Some(file_type_name(tagged_file.file_type()).to_string());
    let container = tagged_file
        .primary_tag()
        .or_else(|| tagged_file.first_tag())
        .map(|t| tag_type_name(t.tag_type()).to_string());

    let metadata = match tagged_file.primary_tag().or_else(|| tagged_file.first_tag()) {
        Some(t) => extract_metadata(t),
        None => Metadata {
            title: None,
            artist: None,
            album: None,
            album_artist: None,
            genre: None,
            comment: None,
            composer: None,
            lyricist: None,
            grouping: None,
            year: None,
            track_number: None,
            track_total: None,
            disc_number: None,
            disc_total: None,
            lyrics: None,
            extras: HashMap::new(),
        },
    };

    let properties = if read_props != 0 {
        let props = tagged_file.properties();
        Some(Properties {
            duration_ms: props.duration().as_millis() as u64,
            bitrate: props.overall_bitrate(),
            sample_rate: props.sample_rate(),
            channels: props.channels(),
            bit_depth: props.bit_depth(),
        })
    } else {
        None
    };

    let pictures = if read_pictures != 0 {
        match tagged_file.primary_tag().or_else(|| tagged_file.first_tag()) {
            Some(t) => extract_pictures(t),
            None => Vec::new(),
        }
    } else {
        Vec::new()
    };

    let raw_tags = if read_raw_tags != 0 {
        extract_raw_tags(&tagged_file)
    } else {
        Vec::new()
    };

    let response = ReadResponse {
        metadata,
        format,
        container,
        properties,
        pictures,
        raw_tags,
    };

    to_c_string(serde_json::to_string(&response).unwrap_or_default())
}

#[no_mangle]
pub extern "C" fn lofty_write_file(
    path: *const c_char,
    patch_json: *const c_char,
) -> i32 {
    clear_error();
    if path.is_null() {
        set_error("Null path");
        return -1;
    }
    if patch_json.is_null() {
        set_error("Null patch");
        return -3;
    }
    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Path is not valid UTF-8");
            return -1;
        }
    };
    let patch_str = match unsafe { CStr::from_ptr(patch_json) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Patch JSON is not valid UTF-8");
            return -3;
        }
    };

    let patch: WritePatch = match serde_json::from_str(patch_str) {
        Ok(p) => p,
        Err(e) => {
            set_error(format!("Invalid patch JSON: {}", e));
            return -3;
        }
    };

    let mut tagged_file = match Probe::open(Path::new(path_str))
        .and_then(|probe| probe.options(ParseOptions::new()).read())
    {
        Ok(f) => f,
        Err(e) => {
            set_error(format!("Could not open or recognize file: {}", e));
            return -1;
        }
    };

    // Capture the primary tag type before borrowing mutably.
    let primary_type = tagged_file.primary_tag_type();

    // Ensure a primary tag exists.
    let tag = if tagged_file.primary_tag_mut().is_some() {
        tagged_file.primary_tag_mut().unwrap()
    } else {
        tagged_file.insert_tag(Tag::new(primary_type));
        match tagged_file.primary_tag_mut() {
            Some(t) => t,
            None => {
                set_error("Could not insert tag for this file type");
                return -2;
            }
        }
    };

    // -- setFields ----------------------------------------------------------
    for (field_name, value) in &patch.set_fields {
        if let Some(prop) = json_field_to_property(field_name) {
            if let Some(key) = item_key_for_property(prop) {
                apply_set_value(tag, key, value);
            }
        }
    }

    // -- clearFields --------------------------------------------------------
    for field_name in &patch.clear_fields {
        if let Some(prop) = json_field_to_property(field_name) {
            if let Some(key) = item_key_for_property(prop) {
                tag.remove_key(key);
            }
        }
    }

    // -- rawMutations -------------------------------------------------------
    // Lofty's `Tag` enum doesn't model arbitrary keys, so we silently skip
    // raw keys it can't map. Most music-editor uses (ISRC, MusicBrainz IDs,
    // ReplayGain, Catalog Number, etc.) are covered by the explicit map.
    for (raw_key, value) in &patch.raw_mutations {
        if let Some(key) = item_key_for_property(raw_key) {
            apply_set_value(tag, key, value);
        }
    }

    // -- pictureOperations --------------------------------------------------
    for op in &patch.picture_operations {
        if let Err(msg) = apply_picture_op(tag, op) {
            set_error(format!("Picture operation failed: {}", msg));
            return -5;
        }
    }

    // -- stripOtherTags -----------------------------------------------------
    if patch.strip_other_tags {
        // Remove every tag that isn't the primary container.
        let other_types: Vec<TagType> = tagged_file
            .tags()
            .iter()
            .map(|t| t.tag_type())
            .filter(|tt| *tt != primary_type)
            .collect();
        for tt in other_types {
            tagged_file.remove(tt);
        }
    }

    match tagged_file.save_to_path(path_str, WriteOptions::default()) {
        Ok(()) => 0,
        Err(e) => {
            set_error(format!("Failed to save file: {}", e));
            -4
        }
    }
}

#[no_mangle]
pub extern "C" fn lofty_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}
