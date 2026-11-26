module embedding_metadata_contract_tests;

import flint.ai.embedding : EmbeddingResultMetadata;
import flint.ai.model : ResultMetadata;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.util : MimeType, MimeTypeUtils;
import std.exception : collectException;
import std.typecons : Nullable, nullable;

@safe:

@("embedding metadata retains default values and supplied document data")
unittest
{
    final class ProviderData
    {
    }

    alias Modality = EmbeddingResultMetadata.ModalityType;
    auto defaults = new EmbeddingResultMetadata();
    assert(defaults.getDocumentId() == "" && defaults.getDocumentId() !is null);
    assert(defaults.getModalityType() == Modality.TEXT);
    assert(defaults.getMimeType() == MimeTypeUtils.TEXT_PLAIN);
    assert(defaults.getDocumentData().isNull());
    assert(defaults !is new EmbeddingResultMetadata());

    auto payload = new ProviderData();
    auto metadata = new EmbeddingResultMetadata("document-1", Modality.IMAGE,
            MimeTypeUtils.IMAGE_PNG, Any.of(payload));
    const ResultMetadata result = metadata;
    assert(cast(const EmbeddingResultMetadata) result is metadata);
    assert(metadata.getDocumentId() == "document-1");
    assert(metadata.getModalityType() == Modality.IMAGE);
    assert(metadata.getMimeType() == MimeTypeUtils.IMAGE_PNG);
    assert(metadata.getDocumentData().get!ProviderData() is payload);
}

@("embedding metadata rejects missing modality and MIME values")
unittest
{
    alias Modality = EmbeddingResultMetadata.ModalityType;
    const missingModality = collectException!IllegalArgumentException(new EmbeddingResultMetadata("document-1",
            Nullable!Modality.init, Nullable!MimeType.init, Any.init));
    assert(missingModality !is null && missingModality.msg == "ModalityType must not be null");

    const missingMime = collectException!IllegalArgumentException(new EmbeddingResultMetadata("document-1",
            nullable(Modality.TEXT), Nullable!MimeType.init, Any.init));
    assert(missingMime !is null && missingMime.msg == "MimeType must not be null");
}

@("embedding modality inference follows MIME compatibility order")
unittest
{
    alias Modality = EmbeddingResultMetadata.ModalityType;
    alias infer = EmbeddingResultMetadata.ModalityUtils.getModalityType;
    assert(infer(Nullable!MimeType.init) == Modality.TEXT);
    assert(infer(MimeTypeUtils.TEXT_PLAIN) == Modality.TEXT);
    assert(infer(nullable(MimeType("audio", "mpeg"))) == Modality.AUDIO);
    assert(infer(MimeType("video", "mp4")) == Modality.VIDEO);
    assert(infer(MimeTypeUtils.IMAGE_PNG) == Modality.IMAGE);
    assert(infer(MimeTypeUtils.ALL) == Modality.IMAGE);

    const unsupported = collectException!IllegalArgumentException(infer(MimeTypeUtils.APPLICATION_JSON));
    assert(unsupported !is null && unsupported.msg == "Unsupported MimeType: application/json");
}
