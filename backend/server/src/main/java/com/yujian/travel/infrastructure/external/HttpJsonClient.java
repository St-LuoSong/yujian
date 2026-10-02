package com.yujian.travel.infrastructure.external;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * 统一的外部 HTTP 调用。
 *
 * 用 JDK 内置的 HttpClient，不引入额外的 HTTP 依赖。
 * 错误信息里只保留状态码与异常描述，绝不回显完整 URL —— 百度地图的 AK 就在 query 里。
 *
 * 提供两种形态：
 * 1. {@link #get} 给普通 JSON 接口（天气、百度地图）；
 * 2. {@link #postJson} 给需要请求头与响应头的协议（MCP Streamable HTTP 要读会话头、
 *    并且响应可能是 `text/event-stream`）；
 * 3. {@link #getBinary} 给返回图片的接口（百度静态底图），字节直接转交，不做 JSON 解析。
 */
@Component
public class HttpJsonClient {
    private static final String USER_AGENT = "yujian-travel-server/0.2";

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;

    public HttpJsonClient(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
        this.httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(3))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();
    }

    public JsonNode get(String endpoint, Map<String, String> query, int timeoutSeconds) {
        URI uri = URI.create(endpoint + "?" + encode(query));
        HttpRequest request = HttpRequest.newBuilder(uri)
            .timeout(Duration.ofSeconds(Math.max(1, timeoutSeconds)))
            .header("Accept", "application/json")
            .header("User-Agent", USER_AGENT)
            .GET()
            .build();
        Exchange exchange = send(request);
        if (!exchange.successful()) {
            throw new ExternalServiceException("HTTP_" + exchange.status(),
                "外部服务返回 " + exchange.status());
        }
        return parse(exchange.body());
    }

    /**
     * POST JSON，并返回状态码、响应头与响应体。
     *
     * 不在这里判断成败：MCP 的握手与会话续期需要按 404/202 分别处理，
     * 把"能不能算成功"交给调用方，比在这里猜要稳妥。
     */
    public Exchange postJson(String endpoint, String body, Map<String, String> headers, int timeoutSeconds) {
        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(endpoint))
            .timeout(Duration.ofSeconds(Math.max(1, timeoutSeconds)))
            .header("Content-Type", "application/json")
            .header("Accept", "application/json, text/event-stream")
            .header("User-Agent", USER_AGENT)
            .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8));
        headers.forEach(builder::header);
        return send(builder.build());
    }

    /**
     * 取二进制响应（目前只有百度静态底图）。
     *
     * 底图是图片而不是 JSON，响应体也不再解析 —— 服务端只做一次取图与缓存，
     * 然后把 PNG 原样转交给客户端，AK 始终留在服务端。
     * 失败信息同样只保留状态码，不回显 URL：AK 就在 query 里。
     */
    public BinaryResponse getBinary(String endpoint, Map<String, String> query, int timeoutSeconds) {
        URI uri = URI.create(endpoint + "?" + encode(query));
        HttpRequest request = HttpRequest.newBuilder(uri)
            .timeout(Duration.ofSeconds(Math.max(1, timeoutSeconds)))
            .header("Accept", "image/png,image/*")
            .header("User-Agent", USER_AGENT)
            .GET()
            .build();
        try {
            HttpResponse<byte[]> response =
                httpClient.send(request, HttpResponse.BodyHandlers.ofByteArray());
            return new BinaryResponse(response.statusCode(),
                response.headers().firstValue("Content-Type").orElse(null), response.body());
        } catch (IOException exception) {
            throw new ExternalServiceException("NETWORK_ERROR", "外部服务连接失败或响应不可读", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new ExternalServiceException("INTERRUPTED", "外部服务调用被中断", exception);
        }
    }

    public JsonNode parse(String body) {
        try {
            return objectMapper.readTree(body);
        } catch (IOException exception) {
            throw new ExternalServiceException("MALFORMED_JSON", "外部服务返回的内容无法解析为 JSON", exception);
        }
    }

    private Exchange send(HttpRequest request) {
        try {
            HttpResponse<String> response = httpClient.send(request,
                HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            return new Exchange(response.statusCode(), response.headers().map(), response.body());
        } catch (IOException exception) {
            throw new ExternalServiceException("NETWORK_ERROR", "外部服务连接失败或响应不可读", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new ExternalServiceException("INTERRUPTED", "外部服务调用被中断", exception);
        }
    }

    private static String encode(Map<String, String> query) {
        return query.entrySet().stream()
            .filter(entry -> entry.getValue() != null)
            .map(entry -> URLEncoder.encode(entry.getKey(), StandardCharsets.UTF_8)
                + "=" + URLEncoder.encode(entry.getValue(), StandardCharsets.UTF_8))
            .collect(Collectors.joining("&"));
    }

    /** 一次二进制 HTTP 往返（底图）。 */
    public record BinaryResponse(int status, String contentType, byte[] body) {
        public boolean successful() {
            return status / 100 == 2 && body != null && body.length > 0;
        }

        /** 上游把 JSON 错误塞进图片响应时用得上：只取前若干字节做判断。 */
        public String bodyPreview() {
            if (body == null) {
                return "";
            }
            int limit = Math.min(body.length, 120);
            return new String(body, 0, limit, StandardCharsets.UTF_8).replaceAll("\\s+", " ");
        }
    }

    /** 一次 HTTP 往返的原始结果。 */
    public record Exchange(int status, Map<String, List<String>> headers, String body) {
        public boolean successful() {
            return status / 100 == 2;
        }

        public String header(String name) {
            List<String> values = headers.get(name.toLowerCase(Locale.ROOT));
            return values == null || values.isEmpty() ? null : values.get(0);
        }
    }
}

