import java.awt.BorderLayout;
import java.lang.management.ManagementFactory;
import java.util.concurrent.CountDownLatch;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.SwingConstants;
import javax.swing.SwingUtilities;

public final class SwingHello {
    private static final CountDownLatch STOP = new CountDownLatch(1);

    public static void main(String[] args) throws Exception {
        SwingUtilities.invokeAndWait(() -> {
            var frame = new JFrame("Hello World");
            frame.setDefaultCloseOperation(JFrame.DO_NOTHING_ON_CLOSE);
            frame.setLayout(new BorderLayout());
            frame.add(new JLabel("Hello World", SwingConstants.CENTER));
            frame.setSize(320, 120);
            frame.setLocationRelativeTo(null);
            frame.setVisible(true);
            if (!frame.isShowing()) {
                throw new IllegalStateException("Swing frame is not showing");
            }
            var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
            System.out.printf("MEMORY_TEST_HEAP init=%d used=%d committed=%d max=%d%n",
                    heap.getInit(), heap.getUsed(), heap.getCommitted(), heap.getMax());
            System.out.println("MEMORY_TEST_READY application=swing frame_visible=true");
            System.out.flush();
        });
        STOP.await();
    }
}
