package com.yujian.travel.infrastructure;

import com.android.apksig.ApkVerifier;
import com.yujian.travel.common.ApiException;
import net.dongliu.apk.parser.ApkFile;
import net.dongliu.apk.parser.bean.ApkMeta;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

import java.io.InputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.cert.X509Certificate;
import java.util.HexFormat;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.regex.Pattern;

/** Verifies an APK as a signed Android artifact, then extracts trusted metadata from it. */
@Component
public class AppReleasePackageInspector {
    private static final Pattern DEBUGGABLE_APPLICATION = Pattern.compile(
        "<application\\b[^>]*\\bandroid:debuggable\\s*=\\s*[\"']true[\"']",
        Pattern.CASE_INSENSITIVE | Pattern.DOTALL);

    /**
     * @param allowDebuggable 是否接受 debuggable APK。只有 DEBUG 通道会传 true：
     *                        调试包的价值就在于"能装上看日志"，把这一条禁掉等于
     *                        把整条内部更新通道关死。
     */
    public InspectedPackage inspect(Path apk, boolean allowDebuggable) {
        ApkVerifier.Result verification;
        try {
            verification = new ApkVerifier.Builder(apk.toFile()).build().verify();
        } catch (Exception exception) {
            throw invalid("APK 签名结构无法解析");
        }
        if (!verification.isVerified()) {
            throw invalid("APK 签名无效或文件已被篡改");
        }

        Set<String> certificates = new LinkedHashSet<>();
        for (X509Certificate certificate : verification.getSignerCertificates()) {
            try {
                certificates.add(sha256(certificate.getEncoded()));
            } catch (Exception exception) {
                throw invalid("APK 签名证书无法读取");
            }
        }
        if (certificates.size() != 1) {
            throw invalid("APK 必须且只能包含一个当前发布证书");
        }

        try (ApkFile apkFile = new ApkFile(apk.toFile())) {
            ApkMeta metadata = apkFile.getApkMeta();
            if (!allowDebuggable && DEBUGGABLE_APPLICATION.matcher(apkFile.getManifestXml()).find()) {
                throw invalid("不允许上传 debuggable APK，请构建正式 Release 包");
            }
            return new InspectedPackage(
                metadata.getPackageName(),
                metadata.getVersionCode() == null ? 0 : metadata.getVersionCode(),
                metadata.getVersionName(),
                integerOrNull(metadata.getMinSdkVersion()),
                integerOrNull(metadata.getTargetSdkVersion()),
                certificates.iterator().next(),
                sha256(apk)
            );
        } catch (ApiException exception) {
            throw exception;
        } catch (IOException | RuntimeException exception) {
            throw invalid("APK 清单无法解析");
        }
    }

    private static Integer integerOrNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return Integer.valueOf(value);
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static String sha256(byte[] value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private static String sha256(Path path) throws IOException {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = Files.newInputStream(path)) {
                byte[] buffer = new byte[64 * 1024];
                int read;
                while ((read = input.read(buffer)) >= 0) {
                    if (read > 0) digest.update(buffer, 0, read);
                }
            }
            return HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private static ApiException invalid(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "APP_RELEASE_APK_INVALID", message);
    }

    public record InspectedPackage(
        String packageName,
        long versionCode,
        String versionName,
        Integer minimumSdk,
        Integer targetSdk,
        String certificateSha256,
        String fileSha256
    ) {
    }
}
