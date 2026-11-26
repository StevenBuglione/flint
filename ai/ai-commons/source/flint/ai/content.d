/*
 * Copyright 2023-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/content/{Content,Media,MediaContent}.java
// Modified by the Flint authors.
module flint.ai.content;

import flint.engine.aot.any : Any;
import flint.java.util : List, Map;
import flint.util : MimeType;
import std.typecons : Nullable;

@safe:

/// Text and metadata shared by chat messages and media-bearing content.
interface Content
{
    /// Returns the text when available. Empty text is a present value.
    Nullable!string getText();

    /// Returns the metadata associated with the content.
    Map!(string, Any) getMetadata();
}

/// Content with an associated list of media.
interface MediaContent : Content
{
    /// Returns the media associated with this content.
    List!Media getMedia();
}

/// The namespace for Spring AI media types.
class Media
{
    @disable this();

    /// MIME types for document, video and image attachments.
    static class Format
    {
        /// Creates the format namespace's default instance.
        this() pure nothrow @nogc
        {
        }

        /// MIME type for application/pdf.
        static immutable MimeType DOC_PDF = MimeType.literal("application", "pdf");

        /// MIME type for text/csv.
        static immutable MimeType DOC_CSV = MimeType.literal("text", "csv");

        /// MIME type for application/msword.
        static immutable MimeType DOC_DOC = MimeType.literal("application", "msword");

        /// MIME type for application/vnd.openxmlformats-officedocument.wordprocessingml.document.
        static immutable MimeType DOC_DOCX = MimeType.literal("application",
                "vnd.openxmlformats-officedocument.wordprocessingml.document");

        /// MIME type for application/vnd.ms-excel.
        static immutable MimeType DOC_XLS = MimeType.literal("application", "vnd.ms-excel");

        /// MIME type for application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.
        static immutable MimeType DOC_XLSX = MimeType.literal("application",
                "vnd.openxmlformats-officedocument.spreadsheetml.sheet");

        /// MIME type for text/html.
        static immutable MimeType DOC_HTML = MimeType.literal("text", "html");

        /// MIME type for text/plain.
        static immutable MimeType DOC_TXT = MimeType.literal("text", "plain");

        /// MIME type for text/markdown.
        static immutable MimeType DOC_MD = MimeType.literal("text", "markdown");

        /// MIME type for video/x-matros.
        static immutable MimeType VIDEO_MKV = MimeType.literal("video", "x-matros");

        /// MIME type for video/quicktime.
        static immutable MimeType VIDEO_MOV = MimeType.literal("video", "quicktime");

        /// MIME type for video/mp4.
        static immutable MimeType VIDEO_MP4 = MimeType.literal("video", "mp4");

        /// MIME type for video/webm.
        static immutable MimeType VIDEO_WEBM = MimeType.literal("video", "webm");

        /// MIME type for video/x-flv.
        static immutable MimeType VIDEO_FLV = MimeType.literal("video", "x-flv");

        /// MIME type for video/mpeg.
        static immutable MimeType VIDEO_MPEG = MimeType.literal("video", "mpeg");

        /// MIME type for video/mpeg.
        static immutable MimeType VIDEO_MPG = MimeType.literal("video", "mpeg");

        /// MIME type for video/x-ms-wmv.
        static immutable MimeType VIDEO_WMV = MimeType.literal("video", "x-ms-wmv");

        /// MIME type for video/3gpp.
        static immutable MimeType VIDEO_THREE_GP = MimeType.literal("video", "3gpp");

        /// MIME type for image/png.
        static immutable MimeType IMAGE_PNG = MimeType.literal("image", "png");

        /// MIME type for image/jpeg.
        static immutable MimeType IMAGE_JPEG = MimeType.literal("image", "jpeg");

        /// MIME type for image/gif.
        static immutable MimeType IMAGE_GIF = MimeType.literal("image", "gif");

        /// MIME type for image/webp.
        static immutable MimeType IMAGE_WEBP = MimeType.literal("image", "webp");
    }
}
