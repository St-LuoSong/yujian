package com.yujian.travel.config;

import com.yujian.travel.service.MediaStorageService;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * 把上传目录挂到只读的 /media/** 路径。
 *
 * 只暴露文件读取，不暴露目录列表；文件名为服务端生成的 UUID，
 * 客户端无法通过构造路径读取上传目录以外的内容。
 */
@Configuration
public class WebMvcConfig implements WebMvcConfigurer {
    private final MediaStorageService mediaStorageService;

    public WebMvcConfig(MediaStorageService mediaStorageService) {
        this.mediaStorageService = mediaStorageService;
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/media/**")
            .addResourceLocations(mediaStorageService.rootLocation())
            .setCachePeriod(86400);
    }
}
