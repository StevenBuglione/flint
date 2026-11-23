package com.example.dash;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DashApplication {

    public static void main(String[] args) {
        SpringApplication application = new SpringApplication(DashApplication.class);
        application.setAddCommandLineProperties(false);
        System.exit(SpringApplication.exit(application.run(args)));
    }
}
