package com.yujian.travel.api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

@SpringBootApplication(scanBasePackages = "com.yujian.travel")
@ConfigurationPropertiesScan("com.yujian.travel.config")
@EntityScan("com.yujian.travel.domain")
@EnableJpaRepositories("com.yujian.travel.repository")
public class YujianTravelApplication {
    public static void main(String[] args) {
        SpringApplication.run(YujianTravelApplication.class, args);
    }
}
