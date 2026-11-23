package com.example.worker;

import jakarta.annotation.PreDestroy;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;
import org.springframework.core.task.TaskRejectedException;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import org.springframework.stereotype.Component;

/** Polls incoming and runs up to --concurrency jobs at a time. */
@Component
public class Worker {

    private final SpoolQueue queue;
    private final JobExecutor executor;
    private final ThreadPoolTaskExecutor pool;
    private final Semaphore slots;
    private final Set<Path> inFlight = ConcurrentHashMap.newKeySet();

    public Worker(SpoolQueue queue, JobExecutor executor, WorkerOptions options) {
        this.queue = queue;
        this.executor = executor;
        this.slots = new Semaphore(options.concurrency());
        this.pool = new ThreadPoolTaskExecutor();
        pool.setCorePoolSize(options.concurrency());
        pool.setMaxPoolSize(options.concurrency());
        pool.setThreadNamePrefix("job-");
        pool.setWaitForTasksToCompleteOnShutdown(true);
        pool.setAwaitTerminationSeconds(5);
        pool.initialize();
    }

    @Scheduled(fixedDelay = 100)
    public void poll() {
        for (Path job : queue.pending()) {
            if (inFlight.contains(job)) {
                continue;
            }
            if (!slots.tryAcquire()) {
                return;
            }
            inFlight.add(job);
            try {
                pool.execute(() -> {
                    try {
                        process(job);
                    } finally {
                        inFlight.remove(job);
                        slots.release();
                    }
                });
            } catch (TaskRejectedException shuttingDown) {
                inFlight.remove(job);
                slots.release();
                return;
            }
        }
    }

    /** Stops taking jobs and waits for the ones in flight. */
    @PreDestroy
    public void stop() {
        pool.shutdown();
    }

    private void process(Path job) {
        long started = System.nanoTime();
        String name = job.getFileName().toString().replaceFirst("\\.json$", "");
        try {
            byte[] content;
            try {
                content = Files.readAllBytes(job);
            } catch (NoSuchFileException taken) {
                return;
            }
            try {
                JobExecutor.Outcome outcome = executor.execute(content);
                queue.writeDone(outcome.id(), outcome.result(), job);
                System.out.printf("done %s %dms%n", outcome.id(), (System.nanoTime() - started) / 1_000_000);
            } catch (JobFailure failure) {
                queue.writeFailed(job, failure.getMessage());
                System.out.printf("failed %s: %s%n", name, failure.getMessage());
            }
        } catch (IOException error) {
            System.out.printf("error %s: %s%n", name, error);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }
}
