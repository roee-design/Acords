import java.net.URL;
import java.nio.file.*;
public class TestSsl {
  public static void main(String[] a) throws Exception {
    String url = "https://plugins.gradle.org/m2/org/gradle/kotlin/gradle-kotlin-dsl-plugins/5.2.0/gradle-kotlin-dsl-plugins-5.2.0.jar";
    try (var in = new URL(url).openStream()) {
      Files.copy(in, Paths.get("test-plugin.jar"));
    }
    System.out.println("DOWNLOAD OK: " + Files.size(Paths.get("test-plugin.jar")));
  }
}
