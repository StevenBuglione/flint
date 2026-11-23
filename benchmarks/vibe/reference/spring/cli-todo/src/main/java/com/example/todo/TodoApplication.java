package com.example.todo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class TodoApplication {

    public static void main(String[] args) {
        SpringApplication application = new SpringApplication(TodoApplication.class);
        application.setAddCommandLineProperties(false);
        System.exit(SpringApplication.exit(application.run(args)));
    }
}
