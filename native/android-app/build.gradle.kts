import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application") version "8.11.2"
    id("org.jetbrains.kotlin.android") version "2.2.0"
}

val fireRepoRoot = rootDir.parentFile?.parentFile
    ?: error("Unable to resolve Fire repository root from $rootDir")
val generatedUniffiKotlinDir = layout.buildDirectory.dir("generated/uniffi/kotlin")
val generatedUniffiJniLibsDir = layout.buildDirectory.dir("generated/uniffi/jniLibs")

val syncFireUniffiBindings = tasks.register<Exec>("syncFireUniffiBindings") {
    val script = fireRepoRoot.resolve("native/android-app/scripts/sync_uniffi_bindings.sh")

    inputs.file(script)
    inputs.file(fireRepoRoot.resolve("Cargo.toml"))
    inputs.file(fireRepoRoot.resolve("Cargo.lock"))
    inputs.dir(fireRepoRoot.resolve("rust"))
    inputs.dir(fireRepoRoot.resolve("third_party/openwire"))
    inputs.dir(fireRepoRoot.resolve("third_party/xlog-rs"))

    outputs.dir(generatedUniffiKotlinDir)
    outputs.dir(generatedUniffiJniLibsDir)

    commandLine(
        "bash",
        script.absolutePath,
        generatedUniffiKotlinDir.get().asFile.absolutePath,
        generatedUniffiJniLibsDir.get().asFile.absolutePath,
    )
}

android {
    namespace = "com.fire.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.fire.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        viewBinding = true
    }

    sourceSets {
        getByName("main") {
            java.srcDir(generatedUniffiKotlinDir)
            jniLibs.srcDir(generatedUniffiJniLibsDir)
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(syncFireUniffiBindings)
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.webkit:webkit:1.13.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("net.java.dev.jna:jna:5.16.0@aar")
}
