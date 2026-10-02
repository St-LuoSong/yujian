package com.yujian.travel.api;

public final class MediaModels {
    private MediaModels() {
    }

    /**
     * 上传结果。
     *
     * url 是可以直接写进景点内容的绝对地址；relativeUrl 便于同源部署时使用；
     * 两个值都由服务端生成，不含客户端可控内容。
     */
    public record ImageUploadResult(String fileName, String url, String relativeUrl, String format,
                                    long sizeBytes, int width, int height) {
    }
}
