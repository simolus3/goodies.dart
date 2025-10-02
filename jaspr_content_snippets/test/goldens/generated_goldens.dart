final generatedSnippets = {
'jaspr_content_snippets|test/goldens/file.drift.snippet.json': {'(full)': r'''<span><span class="keyword">import</span> <span class="string">'foo.bar'</span>;

<span class="keyword">CREATE</span> <span class="keyword">TABLE</span> <span class="class declaration">users</span> (
    <span class="property">id</span> <span class="type">INTEGER</span> <span class="keyword">NOT</span> <span class="keyword">NULL</span> <span class="keyword">PRIMARY</span> <span class="keyword">KEY</span>,
    <span class="property">best_friend</span> <span class="type">INTEGER</span> <span class="keyword">REFERENCES</span> <span class="class">users</span> (<span class="property">id</span>),
    <span class="property">name</span> <span class="type">TEXT</span> <span class="keyword">NOT</span> <span class="keyword">NULL</span>
);

<span class="function declaration">users</span>:
<span class="keyword">SELECT</span> * <span class="keyword">FROM</span> <span class="class">users</span> <span class="keyword">WHERE</span> <span class="property">name</span> = <span class="variable">?</span></span>
''','query': r'''<span><span class="function declaration">users</span>:
<span class="keyword">SELECT</span> * <span class="keyword">FROM</span> <span class="class">users</span> <span class="keyword">WHERE</span> <span class="property">name</span> = <span class="variable">?</span></span>
''',},
'jaspr_content_snippets|test/goldens/stmt.sql.snippet.json': {'(full)': r'''<span><span class="keyword">CREATE</span> <span class="keyword">TABLE</span> <span class="class declaration">users</span> (
    <span class="property">id</span> <span class="type">INTEGER</span> <span class="keyword">NOT</span> <span class="keyword">NULL</span> <span class="keyword">PRIMARY</span> <span class="keyword">KEY</span> <span class="keyword">AUTOINCREMENT</span>,
    <span class="property">name</span> <span class="type">TEXT</span> <span class="keyword">NOT</span> <span class="keyword">NULL</span>
);</span>
''',},
'jaspr_content_snippets|test/goldens/example.dart.snippet.json': {'(full)': r'''<span><span class="keyword">import</span> <span class="string">'dart:async'</span>;

<span class="keyword">import</span> <span class="string"><a href="https://pub.dev/documentation/build/latest/build/build-library.html">'package:build/build.dart'</a></span>;

<span class="keyword">final</span> <span class="keyword">class</span> <span class="class declaration">ExampleBuilder</span> <span class="keyword">extends</span> <span class="class"><a href="https://pub.dev/documentation/build/latest/build/Builder-class.html">Builder</a></span> {
  <span class="annotation">@</span><span class="property annotation">override</span>
  <span class="class">Map</span>&lt;<span class="class">String</span>, <span class="class">List</span>&lt;<span class="class">String</span>&gt;&gt; <span class="keyword">get</span> <span class="property declaration instance">buildExtensions</span> =&gt; <span class="keyword">const</span> {
    <span class="string">'.dart'</span>: [<span class="string">'.snippets'</span>],
  };

  <span class="annotation">@</span><span class="property annotation">override</span>
  <span class="class">FutureOr</span>&lt;<span class="keyword void">void</span>&gt; <span class="method declaration instance">build</span>(<span class="class"><a href="https://pub.dev/documentation/build/latest/build/BuildStep-class.html">BuildStep</a></span> <span class="parameter declaration">buildStep</span>) {
    <span class="keyword control">throw</span> <span class="class constructor">UnimplementedError</span>();
  }

}
</span>
''','outline': r'''<span><span class="keyword">final</span> <span class="keyword">class</span> <span class="class declaration">ExampleBuilder</span> <span class="keyword">extends</span> <span class="class"><a href="https://pub.dev/documentation/build/latest/build/Builder-class.html">Builder</a></span> {
}
</span>
''','buildExtensions': r'''<span>  <span class="annotation">@</span><span class="property annotation">override</span>
  <span class="class">Map</span>&lt;<span class="class">String</span>, <span class="class">List</span>&lt;<span class="class">String</span>&gt;&gt; <span class="keyword">get</span> <span class="property declaration instance">buildExtensions</span> =&gt; <span class="keyword">const</span> {
    <span class="string">'.dart'</span>: [<span class="string">'.snippets'</span>],
  };</span>
''','build': r'''<span>  <span class="annotation">@</span><span class="property annotation">override</span>
  <span class="class">FutureOr</span>&lt;<span class="keyword void">void</span>&gt; <span class="method declaration instance">build</span>(<span class="class"><a href="https://pub.dev/documentation/build/latest/build/BuildStep-class.html">BuildStep</a></span> <span class="parameter declaration">buildStep</span>) {
    <span class="keyword control">throw</span> <span class="class constructor">UnimplementedError</span>();
  }
</span>
''',},
};
