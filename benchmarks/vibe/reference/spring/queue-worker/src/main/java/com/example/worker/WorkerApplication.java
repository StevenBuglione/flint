package com.example.worker;

import java.util.List;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;
import sun.misc.Signal;

@SpringBootApplication
@EnableScheduling
public class WorkerApplication {

    public static void main(String[] args) {
        WorkerOptions options;
        try {
            options = WorkerOptions.parse(args);
        } catch (IllegalArgumentException error) {
            System.err.println("worker: " + error.getMessage());
            System.err.println("usage: worker --spool <dir> [--concurrency <n>]");
            System.exit(2);
            return;
        }
        // SIGTERM and SIGINT close the context, which stops polling and waits for the jobs in flight; exit 0.
        for (String name : List.of("TERM", "INT")) {
            Signal.handle(new Signal(name), signal -> System.exit(0));
        }
        SpringApplication application = new SpringApplication(WorkerApplication.class);
        application.setAddCommandLineProperties(false);
        application.addInitializers(context -> context.getBeanFactory().registerSingleton("workerOptions", options));
        application.run(args);
    }
}
