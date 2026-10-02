package com.yujian.travel.service;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.config.AppProperties;
import jakarta.annotation.PostConstruct;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Iterator;
import java.util.UUID;

/**
 * 景点配图的上传与存储。
 *
 * 安全边界（这些不是可选优化，是公开部署的必要条件）：
 * 1. 文件名由服务端生成 UUID，绝不使用客户端提供的名字，避免路径穿越；
 * 2. 类型判定只看文件头魔数，不信任 Content-Type 与扩展名；
 * 3. 用 ImageIO 的 reader 读取像素尺寸，不解码整张图，同时拦掉超大图；
 * 4. 只允许 JPEG / PNG / GIF 三种 JDK 原生可解析格式，其余明确拒绝。
 *
 * 存储目录默认是 server/data/uploads，已被 .gitignore 忽略；生产环境可用
 * MEDIA_STORAGE_DIR 指向独立数据盘。
 */
@Service
public class MediaStorageService {
    private static final Logger log = LoggerFactory.getLogger(MediaStorageService.class);

    private final AppProperties properties;
    private Path root;

    public MediaStorageService(AppProperties properties) {
        this.properties = properties;
    }

    @PostConstruct
    void initialize() {
        try {
            root = Paths.get(properties.getMedia().getStorageDir()).toAbsolutePath().normalize();
            Files.createDirectories(root);
        } catch (IOException ex) {
            throw new IllegalStateException("无法创建媒体上传目录：" + properties.getMedia().getStorageDir(), ex);
        }
    }

    public StoredImage store(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MEDIA_EMPTY", "请选择要上传的图片");
        }
        long maxBytes = Math.max(1, properties.getMedia().getMaxSizeMb()) * 1024L * 1024L;
        if (file.getSize() > maxBytes) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "MEDIA_TOO_LARGE",
                "图片不能超过 " + properties.getMedia().getMaxSizeMb() + "MB");
        }

        byte[] bytes;
        try {
            bytes = file.getBytes();
        } catch (IOException ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MEDIA_UNREADABLE", "图片读取失败，请重新选择");
        }

        ImageFormat format = ImageFormat.detect(bytes);
        if (format == null) {
            throw new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "MEDIA_TYPE_UNSUPPORTED",
                "只支持 JPEG、PNG、GIF 格式的图片");
        }

        int[] size = readDimensions(bytes);
        int maxDimension = Math.max(256, properties.getMedia().getMaxDimension());
        if (size[0] > maxDimension || size[1] > maxDimension) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MEDIA_DIMENSION_TOO_LARGE",
                "图片尺寸不能超过 " + maxDimension + "×" + maxDimension + " 像素");
        }

        String fileName = UUID.randomUUID().toString().replace("-", "") + "." + format.extension();
        Path target = resolveSafely(fileName);
        try {
            Files.copy(new ByteArrayInputStream(bytes), target, StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException ex) {
            log.error("Failed to persist uploaded media", ex);
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "MEDIA_WRITE_FAILED", "图片保存失败，请稍后再试");
        }
        return new StoredImage(fileName, format.extension(), bytes.length, size[0], size[1]);
    }

    /**
     * 用户社区图片：重新解码后再编码，主动丢掉 EXIF（尤其是 GPS）。
     *
     * 只接受 JPEG / PNG；GIF 会保留帧与元数据，不适合作为公开旅记图片入口。
     */
    public StoredImage storeCommunityImage(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MEDIA_EMPTY", "请选择要上传的图片");
        }
        long maxBytes = Math.max(1, properties.getMedia().getMaxSizeMb()) * 1024L * 1024L;
        if (file.getSize() > maxBytes) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "MEDIA_TOO_LARGE",
                "图片不能超过 " + properties.getMedia().getMaxSizeMb() + "MB");
        }
        byte[] bytes;
        try {
            bytes = file.getBytes();
        } catch (IOException ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MEDIA_UNREADABLE", "图片读取失败，请重新选择");
        }
        ImageFormat format = ImageFormat.detect(bytes);
        if (format != ImageFormat.JPEG && format != ImageFormat.PNG) {
            throw new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "COMMUNITY_MEDIA_TYPE_UNSUPPORTED",
                "旅记图片只支持 JPEG 和 PNG");
        }
        int[] size = readDimensions(bytes);
        if (size[0] > 3000 || size[1] > 3000) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMMUNITY_MEDIA_DIMENSION_TOO_LARGE",
                "旅记图片最长边不能超过 3000 像素");
        }

        BufferedImage decoded;
        try {
            decoded = ImageIO.read(new ByteArrayInputStream(bytes));
        } catch (IOException ex) {
            throw unsupported();
        }
        if (decoded == null) {
            throw unsupported();
        }
        BufferedImage sanitized = redraw(decoded, format);
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try {
            String imageFormat = format == ImageFormat.PNG ? "png" : "jpg";
            if (!ImageIO.write(sanitized, imageFormat, output)) {
                throw unsupported();
            }
        } catch (IOException ex) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "MEDIA_WRITE_FAILED",
                "图片处理失败，请稍后再试");
        }

        byte[] safeBytes = output.toByteArray();
        String fileName = UUID.randomUUID().toString().replace("-", "") + "." + format.extension();
        Path target = resolveSafely(fileName);
        try {
            Files.copy(new ByteArrayInputStream(safeBytes), target, StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException ex) {
            log.error("Failed to persist sanitized community media", ex);
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "MEDIA_WRITE_FAILED",
                "图片保存失败，请稍后再试");
        }
        return new StoredImage(fileName, format.extension(), safeBytes.length, size[0], size[1]);
    }

    private static BufferedImage redraw(BufferedImage source, ImageFormat format) {
        int type = format == ImageFormat.PNG && source.getColorModel().hasAlpha()
            ? BufferedImage.TYPE_INT_ARGB : BufferedImage.TYPE_INT_RGB;
        BufferedImage target = new BufferedImage(source.getWidth(), source.getHeight(), type);
        Graphics2D graphics = target.createGraphics();
        try {
            if (type == BufferedImage.TYPE_INT_RGB) {
                graphics.setColor(java.awt.Color.WHITE);
                graphics.fillRect(0, 0, target.getWidth(), target.getHeight());
            }
            graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            graphics.drawImage(source, 0, 0, null);
        } finally {
            graphics.dispose();
        }
        return target;
    }

    /** 供 Spring 的静态资源处理器使用；目录必须以 / 结尾才是合法的 resource location。 */
    public String rootLocation() {
        String uri = root.toUri().toString();
        return uri.endsWith("/") ? uri : uri + "/";
    }

    /**
     * 对外可访问的绝对地址。
     *
     * 配置了 app.media.base-url 就用它（模拟器、反向代理场景必须配置，
     * 否则会推导出客户端无法访问的 localhost）。
     */
    public String publicUrl(String fileName, HttpServletRequest request) {
        String configured = properties.getMedia().getBaseUrl();
        String base;
        if (configured != null && !configured.isBlank()) {
            base = trimTrailingSlash(configured.trim());
        } else {
            base = request.getScheme() + "://" + request.getServerName() + ":" + request.getServerPort();
        }
        return base + "/media/" + fileName;
    }

    /** 解析并校验文件路径始终落在上传目录内，任何越界请求直接拒绝。 */
    public Path resolveSafely(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MEDIA_NAME_REQUIRED", "缺少文件名");
        }
        Path resolved = root.resolve(fileName).normalize();
        if (!resolved.startsWith(root) || resolved.equals(root)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "MEDIA_PATH_REJECTED", "非法的文件路径");
        }
        return resolved;
    }

    private static int[] readDimensions(byte[] bytes) {
        try (ImageInputStream stream = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
            if (stream == null) {
                throw unsupported();
            }
            Iterator<ImageReader> readers = ImageIO.getImageReaders(stream);
            if (!readers.hasNext()) {
                throw unsupported();
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(stream);
                // 只读取尺寸，不解码像素，避免解压炸弹占用内存。
                return new int[] {reader.getWidth(0), reader.getHeight(0)};
            } finally {
                reader.dispose();
            }
        } catch (IOException ex) {
            throw unsupported();
        }
    }

    private static ApiException unsupported() {
        return new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "MEDIA_TYPE_UNSUPPORTED",
            "只支持 JPEG、PNG、GIF 格式的图片");
    }

    private static String trimTrailingSlash(String value) {
        String result = value;
        while (result.endsWith("/")) {
            result = result.substring(0, result.length() - 1);
        }
        return result;
    }

    public record StoredImage(String fileName, String format, long sizeBytes, int width, int height) {
        public String relativeUrl() {
            return "/media/" + fileName;
        }
    }

    /** 只放行 JDK 原生可解析、且能通过魔数校验的图片格式。 */
    private enum ImageFormat {
        JPEG("jpg"),
        PNG("png"),
        GIF("gif");

        private final String extension;

        ImageFormat(String extension) {
            this.extension = extension;
        }

        String extension() {
            return extension;
        }

        static ImageFormat detect(byte[] bytes) {
            if (bytes.length >= 3 && (bytes[0] & 0xFF) == 0xFF && (bytes[1] & 0xFF) == 0xD8
                && (bytes[2] & 0xFF) == 0xFF) {
                return JPEG;
            }
            if (bytes.length >= 8 && (bytes[0] & 0xFF) == 0x89 && bytes[1] == 'P' && bytes[2] == 'N'
                && bytes[3] == 'G' && (bytes[4] & 0xFF) == 0x0D && (bytes[5] & 0xFF) == 0x0A
                && (bytes[6] & 0xFF) == 0x1A && (bytes[7] & 0xFF) == 0x0A) {
                return PNG;
            }
            if (bytes.length >= 6 && bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F'
                && bytes[3] == '8' && (bytes[4] == '7' || bytes[4] == '9') && bytes[5] == 'a') {
                return GIF;
            }
            return null;
        }
    }
}
