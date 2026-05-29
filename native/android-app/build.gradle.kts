import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application") version "8.11.2"
    id("org.jetbrains.kotlin.android") version "2.2.0"
    id("androidx.navigation.safeargs.kotlin") version "2.8.9"
}

val fireRepoRoot = rootDir.parentFile?.parentFile
    ?: error("Unable to resolve Fire repository root from $rootDir")
val generatedUniffiRootDir = layout.buildDirectory.dir("generated/source/uniffi")

fun registerSyncFireUniffiBindingsTask(
    taskName: String,
    buildTypeName: String,
    rustProfile: String,
) = tasks.register<Exec>(taskName) {
    val script = fireRepoRoot.resolve("native/android-app/scripts/sync_uniffi_bindings.sh")
    val generatedKotlinDir = generatedUniffiRootDir.map { it.dir("$buildTypeName/kotlin") }
    val generatedJniLibsDir = generatedUniffiRootDir.map { it.dir("$buildTypeName/jniLibs") }

    inputs.file(script)
    inputs.file(fireRepoRoot.resolve(".cargo/config.toml"))
    inputs.file(fireRepoRoot.resolve("Cargo.toml"))
    inputs.file(fireRepoRoot.resolve("Cargo.lock"))
    inputs.file(fireRepoRoot.resolve("rust-toolchain.toml"))
    inputs.file(fireRepoRoot.resolve("rust/crates/fire-uniffi/uniffi.toml"))
    inputs.dir(fireRepoRoot.resolve("rust/crates"))
    inputs.dir(fireRepoRoot.resolve("third_party/openwire"))
    inputs.property("fireRustProfile", rustProfile)

    outputs.dir(generatedKotlinDir)
    outputs.dir(generatedJniLibsDir)

    environment("FIRE_BUILD_PROFILE", rustProfile)

    commandLine(
        "bash",
        script.absolutePath,
        generatedKotlinDir.get().asFile.absolutePath,
        generatedJniLibsDir.get().asFile.absolutePath,
    )
}

val generatedDebugUniffiKotlinDir = generatedUniffiRootDir.map { it.dir("debug/kotlin") }
val generatedDebugUniffiJniLibsDir = generatedUniffiRootDir.map { it.dir("debug/jniLibs") }
val generatedReleaseUniffiKotlinDir = generatedUniffiRootDir.map { it.dir("release/kotlin") }
val generatedReleaseUniffiJniLibsDir = generatedUniffiRootDir.map { it.dir("release/jniLibs") }

val syncFireUniffiDebugBindings = registerSyncFireUniffiBindingsTask(
    taskName = "syncFireUniffiDebugBindings",
    buildTypeName = "debug",
    rustProfile = "debug",
)
val syncFireUniffiReleaseBindings = registerSyncFireUniffiBindingsTask(
    taskName = "syncFireUniffiReleaseBindings",
    buildTypeName = "release",
    rustProfile = "release",
)

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
        getByName("debug") {
            java.srcDir(generatedDebugUniffiKotlinDir)
            jniLibs.srcDir(generatedDebugUniffiJniLibsDir)
        }
        getByName("release") {
            java.srcDir(generatedReleaseUniffiKotlinDir)
            jniLibs.srcDir(generatedReleaseUniffiJniLibsDir)
        }
    }
}

tasks.matching { it.name == "preDebugBuild" }.configureEach {
    dependsOn(syncFireUniffiDebugBindings)
}

tasks.matching { it.name == "preDebugUnitTestBuild" }.configureEach {
    dependsOn(syncFireUniffiDebugBindings)
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(syncFireUniffiReleaseBindings)
}

tasks.matching { it.name == "preReleaseUnitTestBuild" }.configureEach {
    dependsOn(syncFireUniffiReleaseBindings)
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
    implementation("androidx.fragment:fragment-ktx:1.8.6")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")
    implementation("androidx.recyclerview:recyclerview:1.4.0")
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
    implementation("androidx.paging:paging-runtime-ktx:3.3.6")
    implementation("androidx.navigation:navigation-fragment-ktx:2.8.9")
    implementation("androidx.navigation:navigation-ui-ktx:2.8.9")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.datastore:datastore-preferences:1.1.4")
    implementation("androidx.webkit:webkit:1.13.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("net.java.dev.jna:jna:5.16.0@aar")
    implementation("io.coil-kt:coil:2.7.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
