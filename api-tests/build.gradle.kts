plugins {
    java
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

dependencies {
    testImplementation(platform("org.junit:junit-bom:5.12.2"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testImplementation("org.junit.platform:junit-platform-launcher")
    testImplementation("org.assertj:assertj-core:3.27.3")
    testImplementation("io.rest-assured:rest-assured:5.5.1")
    testImplementation(platform("com.fasterxml.jackson:jackson-bom:2.18.3"))
    testImplementation("com.fasterxml.jackson.core:jackson-databind")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform {
        excludeTags("classification-probe")
    }
    val classificationFile = layout.buildDirectory.file("failure-classification/$name.jsonl")
    systemProperty("junit.jupiter.extensions.autodetection.enabled", "true")
    systemProperty("qe.failureClassificationPath", classificationFile.get().asFile.absolutePath)
    doFirst {
        classificationFile.get().asFile.delete()
    }
}

tasks.named<Test>("test") {
    useJUnitPlatform {
        excludeTags("integration", "smoke")
    }
}

tasks.register<Test>("integrationTest") {
    group = "verification"
    description = "Runs tests tagged integration."
    outputs.upToDateWhen { false }
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    useJUnitPlatform {
        includeTags("integration")
    }
}

tasks.register<Test>("smokeTest") {
    group = "verification"
    description = "Runs tests tagged smoke."
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    useJUnitPlatform {
        includeTags("smoke")
    }
}
