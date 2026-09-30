# SQS Acknowledgement Semantics PoC

Demonstrates why a `void`-returning `@SqsListener` method must **never** fire off
async work (`CompletableFuture.runAsync(...)`) without joining/propagating its
result, and why that "async, fire-and-forget" pattern silently breaks SQS's
retry/DLQ (dead-letter queue) guarantees.

## The core question

Spring Cloud AWS's SQS integration acknowledges (deletes) a message from the
queue based on whether the annotated `@SqsListener` method **returns normally**
(success) or **throws** (failure) — evaluated either synchronously (`void`
methods) or via a returned `CompletableFuture` (async methods).

If a `void` listener method kicks off background work but returns before that
work finishes/fails, the framework has no way of knowing the work later failed.
It already acknowledged (deleted) the message the moment the method returned.

This repo proves that empirically using two side-by-side listeners against a
real (LocalStack-emulated) SQS queue + dead-letter queue.

## Project layout

- `AsyncFireAndForgetListener` — `void` listener that spawns
  `CompletableFuture.runAsync(() -> { ...; throw ...; })` **without** joining
  it, then returns immediately. Mirrors a real anti-pattern.
- `SyncBlockingListener` — `void` listener that throws directly and
  synchronously. Control case demonstrating correct behaviour.
- Both listeners sleep for 8s before failing, to make the queue's in-flight
  state easy to observe with simple polling.
- `scripts/setup-queues.sh` — creates both queues + their DLQs in LocalStack,
  with `VisibilityTimeout=5s` and `RedrivePolicy.maxReceiveCount=2` (short
  values chosen purely so the whole retry → DLQ cycle happens in seconds
  instead of minutes).
- `scripts/send-messages.sh` — sends one test message to each queue.
- `scripts/observe.sh` — polls and prints both queues' + both DLQs' message
  counts every 2s for 30s, so you can watch ack vs. redelivery happen live.

## Why maxReceiveCount/DLQ can't be configured from Spring

`RedrivePolicy` (`maxReceiveCount` + dead-letter target) and the queue's
default `VisibilityTimeout` are **server-side attributes of the SQS queue
resource itself** — enforced entirely by SQS, not by any consuming client.
There is no Spring Cloud AWS feature to declare these from `application.yml`
or Java config; they must be provisioned onto the queue directly (CLI,
Terraform, CDK, CloudFormation), which is why `setup-queues.sh` uses the AWS
CLI directly rather than any Spring startup logic. What Spring *can* control
is purely how each message is processed once received — concurrency, poll
timeout, message conversion, error handling, and (as a per-listener override
only) visibility timeout.

## Prerequisites

- Docker (this project uses `colima`+`docker`, but any Docker runtime works)
- Java 21 (a JDK 21 toolchain; Gradle wrapper is 8.11 and will not run its
  daemon on JDK 24/25 — see below)
- AWS CLI v2 (`aws --version`)

### JDK 21 note

If your default `java`/`JAVA_HOME` isn't JDK 21, create a local
`gradle.properties` (gitignored, machine-specific) pointing Gradle's own
daemon at a JDK 21 install, e.g.:

```properties
org.gradle.java.home=/path/to/your/jdk-21
```

The app itself targets Java 21 via its Gradle toolchain regardless of which
JDK runs Gradle's daemon.

## Running the demo

**1. Start LocalStack (SQS only):**
```bash
docker run -d --name sqs-ack-poc-localstack -p 4566:4566 -e SERVICES=sqs localstack/localstack:3.8
```
Wait a few seconds, then confirm it's healthy:
```bash
curl -s http://localhost:4566/_localstack/health | grep sqs
```

**2. Create the queues + DLQs:**
```bash
./scripts/setup-queues.sh
```

**3. Run the app** (separate terminal, leave running):
```bash
./gradlew bootRun
```

**4. Send messages and observe** (another terminal):
```bash
./scripts/send-messages.sh && ./scripts/observe.sh
```

## Expected result

| Queue | Ack'd despite failure? | Ends up in DLQ? |
|---|---|---|
| `async-fire-and-forget-queue` | **Yes** — instantly, silently | **Never** |
| `sync-blocking-queue` | No | **Yes** — after `maxReceiveCount` retries |

Watch the app logs: for the async queue, the `"[ASYNC] processing failed"`
error log appears seconds *after* `observe.sh` already shows the message gone
from the queue (`0/0`) — proof the ack didn't wait for the background work at
all.

## Useful AWS CLI commands (against LocalStack)

All commands need `--endpoint-url http://localhost:4566` and *some*
(non-validated) credentials present:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT=http://localhost:4566

# List queues
aws --endpoint-url $ENDPOINT sqs list-queues

# Purge a queue/DLQ
url=$(aws --endpoint-url $ENDPOINT sqs get-queue-url --queue-name sync-blocking-queue-dlq --query 'QueueUrl' --output text)
aws --endpoint-url $ENDPOINT sqs purge-queue --queue-url "$url"

# Inspect a queue's attributes (visibility timeout, redrive policy, counts)
aws --endpoint-url $ENDPOINT sqs get-queue-attributes --queue-url "$url" --attribute-names All
```

## Key takeaway

If a `@SqsListener`-annotated method's contract is `void`, treat it as fully
synchronous. Spring Cloud AWS already dispatches each listener invocation on
its own container-managed thread — spawning further async work inside adds no
concurrency benefit while breaking the framework's ability to detect failure
and correctly retry/dead-letter messages. The only correct way to get real
async processing with preserved ack semantics is to change the listener
method's return type to `CompletableFuture<Void>` and actually return the
future (not `.join()` it), so the framework's `AsyncMessagingMessageListenerAdapter`
awaits it directly.
