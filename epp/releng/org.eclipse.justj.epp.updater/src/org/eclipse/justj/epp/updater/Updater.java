/**
 * Copyright (c) 2026 Eclipse contributors and others.
 *
 * This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License 2.0
 * which accompanies this distribution, and is available at
 * https://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 */
package org.eclipse.justj.epp.updater;


import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse.BodyHandlers;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.Calendar;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Pattern;
import java.util.zip.ZipInputStream;


public class Updater
{
  private static final String JUSTJ_JRES_URL = "https://download.eclipse.org/justj/jres/25/updates/release/25.0.3.v20260715-1121";

  private static final String COPYRIGHT_YEAR = Integer.toString(Calendar.getInstance().get(Calendar.YEAR));

  private static final String JRE_ID = "org.eclipse.justj.openjdk.hotspot.jre.full";

  private static final Pattern VERSION_PATTERN = Pattern.compile("(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<micro>\\d+)\\.(?<qualifier>.*)");

  private static final Pattern JRE_IU_PATTERN = Pattern.compile("<unit id='" + JRE_ID + ".(?<os>linux|macosx|win32).(?<arch>[^.]+)' version='(?<version>[^']+)'>");

  private Path root;

  public static void main(String[] args) throws IOException
  {
    var currentWorkingDirectory = Path.of(".").toRealPath();
    if (!currentWorkingDirectory.toString().replace("\\", "/").endsWith("epp/releng/org.eclipse.justj.epp.updater"))
    {
      throw new RuntimeException("Expecting to run this from the org.eclipse.epp.releng.updater project");
    }

    var eppRoot = currentWorkingDirectory.resolve("../..").toRealPath();
    new Updater(eppRoot).update();
  }

  private final Map<Path, String> contents = new LinkedHashMap<>();

  private final Set<JRE> jres = new TreeSet<JRE>();

  private final String version;

  private final String jreMajorVersion;

  private final String jreVersion;

  private final String nextJREVersion;

  public Updater(Path root) throws IOException
  {
    this.root = root;
    try (var zip = new ZipInputStream(getContents(JUSTJ_JRES_URL + "/content.jar")))
    {
      zip.getNextEntry();
      var contentMetadata = new String(zip.readAllBytes(), StandardCharsets.UTF_8);
      var versions = new HashSet<String>();
      for (var matcher = JRE_IU_PATTERN.matcher(contentMetadata); matcher.find();)
      {
        jres.add(new JRE(matcher.group("os"), matcher.group("arch")));
        versions.add(matcher.group("version"));
      }

      if (jres.isEmpty() || versions.size() != 1)
      {
        throw new IllegalStateException("The update site is not well formed.");
      }
      jreVersion = versions.iterator().next();
      var matcher = VERSION_PATTERN.matcher(jreVersion);
      if (!matcher.matches())
      {
        throw new IllegalStateException("The version is not well formed: " + jreVersion);
      }

      jreMajorVersion = matcher.group("major");
      nextJREVersion = (Integer.parseInt(jreMajorVersion) + 1) + ".0.0";
      version = jreMajorVersion + "." + matcher.group("minor") + "." + matcher.group("micro");

      return;
    }
  }

  private String getContent(Path path) throws IOException
  {
    return contents.containsKey(path) ? contents.get(path) : Files.readString(path);
  }

  private void apply(Path path, String pattern, String... replacements) throws IOException
  {
    var content = getContent(path);
    var matcher = Pattern.compile(pattern).matcher(content);
    if (matcher.find())
    {
      var modifiedContent = new StringBuilder(content);
      var offset = 0;
      do
      {
        var delta = modifiedContent.length();
        for (var group = matcher.groupCount(); group >= 1; --group)
        {
          modifiedContent.replace(offset + matcher.start(group), offset + matcher.end(group), replacements[group - 1]);
        }
        delta -= modifiedContent.length();
        offset -= delta;
      }
      while (matcher.find());
      if (!modifiedContent.toString().equals(content))
      {
        contents.put(path, modifiedContent.toString());
      }
    }
  }

  private void visit(Path file) throws IOException
  {
    var fileName = file.getFileName().toString();

    try
    {
      if (!fileName.endsWith(".class") && !fileName.endsWith(".png"))
      {
        apply(file, "Copyright \\(c\\) (20\\d\\d)", COPYRIGHT_YEAR);
      }
    }
    catch (IOException ex)
    {
      throw new RuntimeException(file + ": " + ex.getLocalizedMessage(), ex);
    }

    if (fileName.equals("feature.xml"))
    {
      apply(file, "version=\"([0-9.]+)\\.qualifier\"", version);
    }
    else if (fileName.equals("pom.xml"))
    {
      apply(file, "(?s)</parent>.*<version>([0-9.]+)-SNAPSHOT</version>", version);
      apply(file, "      <id>justj-jres</id>[\r\n ]+<url>https://download.eclipse.org/justj/jres/(\\d+)/updates/release/latest</url>", jreMajorVersion);
      apply(file, "<executionEnvironment>" + JRE_ID + "-(\\d+)</executionEnvironment>", jreMajorVersion);
    }
    else if (fileName.equals("MANIFEST.MF"))
    {
      apply(file, "Require-Bundle: " + JRE_ID + ";bundle-version=\"([^\"]+)\"", "[" + jreVersion + "," + nextJREVersion + ")");
      apply(file, "Bundle-Version: ([0-9.]+).qualifier", version);
    }
    else if (fileName.equals("category.xml"))
    {
      apply(file, "<repository-reference location=\"https://download.eclipse.org/justj/jres/([0-9]+)/updates/release/latest\"", jreMajorVersion);
    }
  }

  private void update() throws IOException
  {
    Files.walkFileTree(root, new SimpleFileVisitor<Path>()
      {
        @Override
        public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException
        {
          visit(file);
          return super.visitFile(file, attrs);
        }

        @Override
        public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException
        {
          String fileName = dir.getFileName().toString();
          if ("target".equals(fileName) || fileName.startsWith(".") || dir.endsWith("META-INF/maven"))
          {
            return FileVisitResult.SKIP_SUBTREE;
          }
          Path relativePath = root.relativize(dir);
          if (relativePath.startsWith("updates"))
          {
            return FileVisitResult.SKIP_SUBTREE;
          }
          return super.preVisitDirectory(dir, attrs);
        }
      });

    saveModifiedContents();
  }

  private void saveModifiedContents() throws IOException
  {
    for (var entry : contents.entrySet())
    {
      Files.writeString(entry.getKey(), entry.getValue());
    }
  }

  private InputStream getContents(String location) throws IOException
  {
    try
    {
      var uri = URI.create(location);
      var httpClient = HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NORMAL).build();
      var requestBuilder = HttpRequest.newBuilder(uri).GET();
      var request = requestBuilder.build();
      var response = httpClient.send(request, BodyHandlers.ofInputStream());
      var statusCode = response.statusCode();
      if (statusCode != 200)
      {
        throw new IOException("status code " + statusCode + " -> " + uri);
      }
      return response.body();
    }
    catch (InterruptedException e)
    {
      throw new IOException(e);
    }
  }

  private static record JRE(String os, String arch) implements Comparable<JRE>
  {
    @Override
    public int compareTo(JRE o)
    {
      var comparision = os.compareTo(o.os);
      if (comparision == 0)
      {
        comparision = arch.compareTo(o.arch);
      }
      return comparision;
    }
  }
}
