package com.yujian.travel.service;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.config.AppProperties;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;

import javax.imageio.ImageIO;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class MediaStorageServiceTest {
    @TempDir
    Path tempDir;

    @Test
    void communityImageIsReencodedBeforeStorage() throws Exception {
        AppProperties properties = new AppProperties();
        properties.getMedia().setStorageDir(tempDir.toString());
        MediaStorageService service = new MediaStorageService(properties);
        service.initialize();

        byte[] png = pngBytes();
        MediaStorageService.StoredImage stored = service.storeCommunityImage(
            new MockMultipartFile("file", "photo.png", "image/png", png));

        assertThat(stored.format()).isEqualTo("png");
        assertThat(stored.width()).isEqualTo(24);
        assertThat(stored.height()).isEqualTo(16);
        assertThat(Files.readAllBytes(service.resolveSafely(stored.fileName()))).isNotEmpty();
    }

    @Test
    void communityImageRejectsUnsupportedFormat() {
        AppProperties properties = new AppProperties();
        properties.getMedia().setStorageDir(tempDir.toString());
        MediaStorageService service = new MediaStorageService(properties);
        service.initialize();

        assertThatThrownBy(() -> service.storeCommunityImage(
            new MockMultipartFile("file", "note.txt", "text/plain", "not an image".getBytes())))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("只支持 JPEG 和 PNG");
    }

    private byte[] pngBytes() throws Exception {
        BufferedImage image = new BufferedImage(24, 16, BufferedImage.TYPE_INT_ARGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setColor(Color.CYAN);
        graphics.fillRect(0, 0, image.getWidth(), image.getHeight());
        graphics.dispose();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        ImageIO.write(image, "png", output);
        return output.toByteArray();
    }
}
