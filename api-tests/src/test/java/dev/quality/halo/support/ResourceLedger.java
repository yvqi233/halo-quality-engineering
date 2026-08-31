package dev.quality.halo.support;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

public final class ResourceLedger {
    private final Deque<ResourceRef> resources = new ArrayDeque<>();

    public void record(ResourceRef ref) {
        resources.addFirst(ref);
    }

    public List<CleanupFailure> cleanup(ThrowingConsumer<ResourceRef> delete) {
        List<CleanupFailure> failures = new ArrayList<>();
        resources.forEach(ref -> {
            try {
                delete.accept(ref);
            } catch (Exception error) {
                failures.add(new CleanupFailure(ref.name(), error.getMessage()));
            }
        });
        return List.copyOf(failures);
    }
}

@FunctionalInterface
interface ThrowingConsumer<T> {
    void accept(T value) throws Exception;
}

record CleanupFailure(String resourceName, String message) {}
