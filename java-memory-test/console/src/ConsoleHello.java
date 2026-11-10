import java.util.concurrent.CountDownLatch;
import java.lang.management.ManagementFactory;

public final class ConsoleHello {
    private static final String MESSAGE = "Hello World";
    private static final CountDownLatch STOP = new CountDownLatch(1);

    public static void main(String[] args) throws InterruptedException {
        System.out.println(MESSAGE);
        var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
        System.out.printf("MEMORY_TEST_HEAP init=%d used=%d committed=%d max=%d%n",
                heap.getInit(), heap.getUsed(), heap.getCommitted(), heap.getMax());
        System.out.println("MEMORY_TEST_READY application=console");
        System.out.flush();
        STOP.await();
    }
}
