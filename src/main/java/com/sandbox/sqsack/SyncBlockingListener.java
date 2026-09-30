package com.sandbox.sqsack;

import java.time.Instant;
import io.awspring.cloud.sqs.annotation.SqsListener;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * Control case: a plain synchronous listener that throws directly. The exception
 * propagates out of listen() before the framework acknowledges the message, so it
 * should NOT be deleted and should reappear after the visibility timeout.
 */
@Slf4j
@Component
public class SyncBlockingListener {

    @SqsListener(queueNames = "${app.queue-sync}")
    public void listen(final String message) {
        log.info("[SYNC] received at {}: {}", Instant.now(), message);
//        sleepQuietly(8);
        throw new RuntimeException("Simulated processing failure (SYNC, blocking)");
    }

    private static void sleepQuietly(final long seconds) {
        try {
            Thread.sleep(java.time.Duration.ofSeconds(seconds));
        } catch (final InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
