package dev.quality.halo.support;

public record ResourceRef(String apiGroup, String version, String plural, String name) {
    public static ResourceRef scoped(
            RunIdentity runIdentity,
            String apiGroup,
            String version,
            String plural,
            String logicalSuffix) {
        return new ResourceRef(apiGroup, version, plural, runIdentity.prefix() + "-" + logicalSuffix);
    }
}
