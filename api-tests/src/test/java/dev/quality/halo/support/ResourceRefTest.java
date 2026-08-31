package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ResourceRefTest {
    @Test
    void scopesResourceNamesToTheRunIdentity() {
        var identity = new RunIdentity("20260831t010203z-1234abcd", "chromium-1");

        var resource = ResourceRef.scoped(
                identity, "content.halo.run", "v1alpha1", "posts", "article-a");

        assertThat(resource)
                .isEqualTo(new ResourceRef(
                        "content.halo.run",
                        "v1alpha1",
                        "posts",
                        "qe-20260831t010203z-chromium-1-1234abcd-article-a"));
    }
}
