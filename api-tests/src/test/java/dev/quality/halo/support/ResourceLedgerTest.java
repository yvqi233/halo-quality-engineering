package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class ResourceLedgerTest {
    @Test
    void cleanupRunsInReverseAndKeepsEveryFailure() {
        var ledger = new ResourceLedger();
        ledger.record(new ResourceRef("halo.run", "v1alpha1", "users", "user-a"));
        ledger.record(new ResourceRef("content.halo.run", "v1alpha1", "posts", "post-b"));
        List<String> calls = new ArrayList<>();

        var failures = ledger.cleanup(ref -> {
            calls.add(ref.name());
            if (ref.name().equals("post-b")) throw new IOException("delete failed");
        });

        assertThat(calls).containsExactly("post-b", "user-a");
        assertThat(failures).extracting(CleanupFailure::resourceName).containsExactly("post-b");
    }
}
