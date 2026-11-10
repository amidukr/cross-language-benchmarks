package benchmarks.quarkushello;

import java.lang.management.ManagementFactory;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.event.Observes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/hello-world")
public class HelloResource {
    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String helloWorld() {
        return "Hello World";
    }

    void ready(@Observes StartupEvent event) {
        var heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
        System.out.printf("MEMORY_TEST_HEAP init=%d used=%d committed=%d max=%d%n",
                heap.getInit(), heap.getUsed(), heap.getCommitted(), heap.getMax());
        System.out.println("MEMORY_TEST_READY application=quarkus port=8080");
        System.out.flush();
    }
}
