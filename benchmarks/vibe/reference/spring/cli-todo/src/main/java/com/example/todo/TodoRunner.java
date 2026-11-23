package com.example.todo;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.ExitCodeGenerator;
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Component;
import picocli.CommandLine;

/** Runs the command line through picocli, creating its commands as Spring beans. */
@Component
public class TodoRunner implements CommandLineRunner, ExitCodeGenerator {

    private final ApplicationContext context;
    private int exitCode;

    public TodoRunner(ApplicationContext context) {
        this.context = context;
    }

    @Override
    public void run(String... args) {
        CommandLine.IFactory factory = new CommandLine.IFactory() {
            @Override
            public <K> K create(Class<K> type) throws Exception {
                K bean = context.getBeanProvider(type).getIfAvailable();
                return bean != null ? bean : CommandLine.defaultFactory().create(type);
            }
        };
        exitCode = new CommandLine(TodoCommand.class, factory)
                .setExecutionExceptionHandler((error, commandLine, parseResult) -> {
                    commandLine.getErr().println("todo: " + error.getMessage());
                    return error instanceof TodoException todo ? todo.exitCode() : 4;
                })
                .execute(args);
    }

    @Override
    public int getExitCode() {
        return exitCode;
    }
}
