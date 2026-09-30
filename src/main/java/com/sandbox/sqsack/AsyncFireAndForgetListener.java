package com.sandbox.sqsack;

import java.time.Instant;
import java.util.concurrent.CompletableFuture;
import io.awspring.cloud.sqs.annotation.SqsListener;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * Mirrors the "fire-and-forget" pattern under test: the listener method is {@code void},
 * kicks off async work via {@link CompletableFuture#runAsync}, but does NOT join/await it
 * before returning. Any exception thrown inside the async task is only visible to the
 * exceptionally() callback - it never propagates back out of listen().
 */
@Slf4j
@Component
public class AsyncFireAndForgetListener {

    @SqsListener(queueNames = "${app.queue-async}")
    public void listen(final String message) {
        log.info("[ASYNC] received at {}: {}", Instant.now(), message);

        CompletableFuture.runAsync(() -> {
                log.info("[ASYNC] processing on thread {}", Thread.currentThread().getName());
//                sleepQuietly(8);
                throw new RuntimeException("Simulated processing failure (ASYNC, fire-and-forget)");
            })
            .thenRun(() -> log.info("[ASYNC] processing completed successfully"))
            .exceptionally(ex -> {
                log.error("[ASYNC] processing failed, but listener method already returned normally", ex);
                return null;
            });

        log.info("[ASYNC] listen() returning normally now, async task may still be running/failing");
    }

    private static void sleepQuietly(final long seconds) {
        try {
            Thread.sleep(java.time.Duration.ofSeconds(seconds));
        } catch (final InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
