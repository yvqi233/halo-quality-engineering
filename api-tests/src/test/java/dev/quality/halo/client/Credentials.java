package dev.quality.halo.client;

import java.util.Objects;

public record Credentials(String username, String password) {
    public Credentials {
        Objects.requireNonNull(username, "username");
        Objects.requireNonNull(password, "password");
    }
}
