module media_format_tests;

import flint.ai.content : Media;
import flint.util : MimeType;

@safe:

@("media format constants preserve the Spring media types")
unittest
{
    struct Example
    {
        MimeType value;
        string text;
    }

    Example[] samples = [
        Example(Media.Format.DOC_PDF, "application/pdf"), Example(Media.Format.DOC_CSV,
                "text/csv"), Example(Media.Format.DOC_DOC, "application/msword"),
        Example(Media.Format.DOC_DOCX, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
        Example(Media.Format.DOC_XLS, "application/vnd.ms-excel"),
        Example(Media.Format.DOC_XLSX, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
        Example(Media.Format.DOC_HTML, "text/html"), Example(Media.Format.DOC_TXT, "text/plain"),
        Example(Media.Format.DOC_MD, "text/markdown"),
        Example(Media.Format.VIDEO_MKV, "video/x-matros"),
        Example(Media.Format.VIDEO_MOV, "video/quicktime"),
        Example(Media.Format.VIDEO_MP4, "video/mp4"), Example(Media.Format.VIDEO_WEBM,
                "video/webm"), Example(Media.Format.VIDEO_FLV, "video/x-flv"),
        Example(Media.Format.VIDEO_MPEG, "video/mpeg"), Example(Media.Format.VIDEO_MPG,
                "video/mpeg"), Example(Media.Format.VIDEO_WMV, "video/x-ms-wmv"),
        Example(Media.Format.VIDEO_THREE_GP, "video/3gpp"),
        Example(Media.Format.IMAGE_PNG, "image/png"), Example(Media.Format.IMAGE_JPEG,
                "image/jpeg"), Example(Media.Format.IMAGE_GIF, "image/gif"),
        Example(Media.Format.IMAGE_WEBP, "image/webp"),
    ];
    foreach (ref const example; samples)
        assert(example.value.toString() == example.text, example.value.toString() ~ " != " ~ example.text);
}
