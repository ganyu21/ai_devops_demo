package com.lab.shortlink;

import com.lab.shortlink.config.ShortlinkProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(ShortlinkProperties.class)
public class ShortlinkApplication {

    public static void main(String[] args) {
        SpringApplication.run(ShortlinkApplication.class, args);
    }
}
