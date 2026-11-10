package benchmarks.springhello;

import java.lang.management.ManagementFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class SpringHelloApplication {
    public static void main(String[] args) {
        SpringApplication.run(SpringHelloApplication.class, args);
    }

    @GetMapping(value = "/hello-world", produces = MediaType.TEXT_PLAIN_VALUE)
    public String helloWorld() {
        return "Hello World";
    }

    @EventListener(ApplicationReadyEvent.class)
    public void ready() {
        var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
        System.out.printf("MEMORY_TEST_HEAP init=%d used=%d committed=%d max=%d%n",
                heap.getInit(), heap.getUsed(), heap.getCommitted(), heap.getMax());
        System.out.println("MEMORY_TEST_READY application=spring-boot port=8080");
        System.out.flush();
    }
}
