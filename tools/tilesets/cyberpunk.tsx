<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.10.2" name="cyberpunk" tilewidth="32" tileheight="32" spacing="0" margin="0" tilecount="256" columns="16">
 <image source="cyberpunk.png" width="512" height="512"/>
 <tile id="0">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="1" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="2" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="3" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="4" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="5" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="6" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="7" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="8" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="9" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="10" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="11" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="12">
  <properties>
   <property name="ground" value="hazard floor"/>
  </properties>
 </tile>
 <tile id="13">
  <properties>
   <property name="ground" value="metal"/>
  </properties>
 </tile>
 <tile id="14" probability="0.12">
  <properties>
   <property name="ground" value="metal"/>
  </properties>
 </tile>
 <tile id="15" probability="0.12">
  <properties>
   <property name="ground" value="asphalt"/>
  </properties>
 </tile>
 <tile id="16">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="ground" value="ruin roof"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="17" probability="0.12">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="ground" value="ruin roof (collapsed)"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="18">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="ground" value="toxic sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="19" probability="0.12">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="ground" value="toxic sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="20" probability="0.12">
  <properties>
   <property name="ground" value="metal"/>
  </properties>
 </tile>
 <tile id="32">
  <properties>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
 </tile>
 <tile id="33">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="16" height="32"/>
  </objectgroup>
 </tile>
 <tile id="34">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
  </objectgroup>
 </tile>
 <tile id="35">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="16" y="0" width="16" height="32"/>
  </objectgroup>
 </tile>
 <tile id="36">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
  </objectgroup>
 </tile>
 <tile id="37">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
   <object id="2" type="collision" x="0" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="38">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="39">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
   <object id="2" type="collision" x="16" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="40">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
   <object id="2" type="collision" x="0" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="41">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="42">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
   <object id="2" type="collision" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="43">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
   <object id="2" type="collision" x="0" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="44">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="45">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
   <object id="2" type="collision" x="16" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="46">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
   <object id="2" type="collision" x="0" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="47">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="48">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="49">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="50">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
   <object id="2" type="collision" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="51">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="52">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="53">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="54">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="55">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="56">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="57">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="58">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="59">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="60">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="61">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="62">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="63">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="64">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="65">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="66">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="67">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="68">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="69">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="70">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="71">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="72">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="73">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="74">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="75">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="76">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="77">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="78">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-ruin"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="80">
  <properties>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
 </tile>
 <tile id="81">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="16" height="32"/>
  </objectgroup>
 </tile>
 <tile id="82">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
  </objectgroup>
 </tile>
 <tile id="83">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="16" y="0" width="16" height="32"/>
  </objectgroup>
 </tile>
 <tile id="84">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
  </objectgroup>
 </tile>
 <tile id="85">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
   <object id="2" type="collision" x="0" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="86">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="87">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
   <object id="2" type="collision" x="16" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="88">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
   <object id="2" type="collision" x="0" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="89">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="90">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
   <object id="2" type="collision" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="91">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
   <object id="2" type="collision" x="0" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="92">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="93">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="16" width="32" height="16"/>
   <object id="2" type="collision" x="16" y="0" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="94">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
   <object id="2" type="collision" x="0" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="95">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="96">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="97">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="98">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="16"/>
   <object id="2" type="collision" x="16" y="16" width="16" height="16"/>
  </objectgroup>
 </tile>
 <tile id="99">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="100">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="101">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="102">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="103">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="104">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="105">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="106">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="107">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="108">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="109">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="110">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="111">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="112">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="113">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="114">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="115">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="116">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="117">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="118">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="119">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="120">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="121">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="122">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="123">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="124">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="125">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="126">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="blob" value="asphalt-sludge"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="128">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="129">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="130">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="131">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="132">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="133">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="134">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="135">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="136">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="137">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="138">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="139">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="140">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="141">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="142">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="143">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="144">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="145">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="146">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="147">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="148">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="149">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="150">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="151">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="152">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="153">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="154">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="155">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="156">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="157">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="158">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="159">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="160">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="161">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="162">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="163">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="164">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="165">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="166">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="167">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="168">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="169">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="170">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="171">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="172">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="173">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="174">
  <properties>
   <property name="blob" value="asphalt-metal"/>
  </properties>
 </tile>
 <tile id="176">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="rubble_small"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="1" width="32" height="31"/>
  </objectgroup>
 </tile>
 <tile id="177">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="rubble_large"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="178">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="rubble_large"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="2" width="32" height="30"/>
  </objectgroup>
 </tile>
 <tile id="179">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="wrecked_car_v"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="5" y="3" width="24" height="29"/>
  </objectgroup>
 </tile>
 <tile id="180">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="wrecked_car_h"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="3" y="5" width="29" height="25"/>
  </objectgroup>
 </tile>
 <tile id="181">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="wrecked_car_h"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="5" width="31" height="25"/>
  </objectgroup>
 </tile>
 <tile id="182">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="barrel_purple"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="6" y="6" width="22" height="23"/>
  </objectgroup>
 </tile>
 <tile id="183">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="barrel_toxic"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="6" y="6" width="22" height="23"/>
  </objectgroup>
 </tile>
 <tile id="184">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="neon_kiosk"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="1" y="3" width="31" height="29"/>
  </objectgroup>
 </tile>
 <tile id="185">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="neon_kiosk"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="3" width="32" height="29"/>
  </objectgroup>
 </tile>
 <tile id="186">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="vending_broken"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="4" y="2" width="26" height="30"/>
  </objectgroup>
 </tile>
 <tile id="187">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="terminal"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="5" y="3" width="24" height="29"/>
  </objectgroup>
 </tile>
 <tile id="188">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="holo_billboard"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="3" y="3" width="29" height="29"/>
  </objectgroup>
 </tile>
 <tile id="189">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="holo_billboard"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="3" width="31" height="29"/>
  </objectgroup>
 </tile>
 <tile id="190">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="neon_sign"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="1" y="5" width="31" height="25"/>
  </objectgroup>
 </tile>
 <tile id="191">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="neon_sign"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="5" width="32" height="25"/>
  </objectgroup>
 </tile>
 <tile id="192">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="crate"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="3" y="3" width="28" height="29"/>
  </objectgroup>
 </tile>
 <tile id="193">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="rubble_large"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="194">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="rubble_large"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="32"/>
  </objectgroup>
 </tile>
 <tile id="195">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="wrecked_car_v"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="5" y="0" width="24" height="32"/>
  </objectgroup>
 </tile>
 <tile id="196">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="dumpster"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="2" y="5" width="30" height="27"/>
  </objectgroup>
 </tile>
 <tile id="197">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="dumpster"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="5" width="32" height="27"/>
  </objectgroup>
 </tile>
 <tile id="198">
  <properties>
   <property name="prop" value="steam_vent"/>
  </properties>
 </tile>
 <tile id="199">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="broken_pillar"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="6" y="2" width="22" height="27"/>
  </objectgroup>
 </tile>
 <tile id="200">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="neon_streetlight"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="6" y="3" width="20" height="26"/>
  </objectgroup>
 </tile>
 <tile id="201">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="satellite_dish"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="3" y="3" width="29" height="29"/>
  </objectgroup>
 </tile>
 <tile id="202">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="satellite_dish"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="3" width="31" height="29"/>
  </objectgroup>
 </tile>
 <tile id="203">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="drone_wreck"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="1" y="1" width="31" height="31"/>
  </objectgroup>
 </tile>
 <tile id="204">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="holo_billboard"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="3" y="0" width="29" height="32"/>
  </objectgroup>
 </tile>
 <tile id="205">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="holo_billboard"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="31" height="32"/>
  </objectgroup>
 </tile>
 <tile id="206">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="barricade"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="1" y="11" width="31" height="18"/>
  </objectgroup>
 </tile>
 <tile id="207">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="barricade"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="11" width="32" height="18"/>
  </objectgroup>
 </tile>
 <tile id="208">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <tile id="209">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <tile id="210">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <tile id="211">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="generator"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="5" width="32" height="27"/>
  </objectgroup>
 </tile>
 <tile id="212">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="generator"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="5" width="31" height="27"/>
  </objectgroup>
 </tile>
 <tile id="213">
  <properties>
   <property name="prop" value="loose_cables"/>
  </properties>
 </tile>
 <tile id="217">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="satellite_dish"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="3" y="0" width="29" height="32"/>
  </objectgroup>
 </tile>
 <tile id="218">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="satellite_dish"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="31" height="32"/>
  </objectgroup>
 </tile>
 <tile id="224">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <tile id="225">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <tile id="226">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <tile id="227">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="generator"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="32" height="30"/>
  </objectgroup>
 </tile>
 <tile id="228">
  <properties>
   <property name="collides" type="bool" value="true"/>
   <property name="prop" value="generator"/>
  </properties>
  <objectgroup draworder="index" id="2">
   <object id="1" type="collision" x="0" y="0" width="31" height="30"/>
  </objectgroup>
 </tile>
 <tile id="240">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <tile id="241">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <tile id="242">
  <properties>
   <property name="prop" value="portal_hexpad"/>
  </properties>
 </tile>
 <wangsets>
  <wangset name="asphalt-ruin" type="mixed" tile="78">
   <wangcolor name="asphalt" color="#3070ff" tile="32" probability="1"/>
   <wangcolor name="ruin" color="#ff3070" tile="78" probability="1"/>
   <wangtile tileid="32" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="33" wangid="1,1,1,1,1,1,2,1"/>
   <wangtile tileid="34" wangid="1,1,1,1,2,1,1,1"/>
   <wangtile tileid="35" wangid="1,1,2,1,1,1,1,1"/>
   <wangtile tileid="36" wangid="2,1,1,1,1,1,1,1"/>
   <wangtile tileid="37" wangid="1,1,1,1,2,1,2,1"/>
   <wangtile tileid="38" wangid="1,1,2,1,1,1,2,1"/>
   <wangtile tileid="39" wangid="1,1,2,1,2,1,1,1"/>
   <wangtile tileid="40" wangid="2,1,1,1,1,1,2,1"/>
   <wangtile tileid="41" wangid="2,1,1,1,2,1,1,1"/>
   <wangtile tileid="42" wangid="2,1,2,1,1,1,1,1"/>
   <wangtile tileid="43" wangid="1,1,1,1,2,2,2,1"/>
   <wangtile tileid="44" wangid="1,1,2,1,2,1,2,1"/>
   <wangtile tileid="45" wangid="1,1,2,2,2,1,1,1"/>
   <wangtile tileid="46" wangid="2,1,1,1,1,1,2,2"/>
   <wangtile tileid="47" wangid="2,1,1,1,2,1,2,1"/>
   <wangtile tileid="48" wangid="2,1,2,1,1,1,2,1"/>
   <wangtile tileid="49" wangid="2,1,2,1,2,1,1,1"/>
   <wangtile tileid="50" wangid="2,2,2,1,1,1,1,1"/>
   <wangtile tileid="51" wangid="1,1,2,1,2,2,2,1"/>
   <wangtile tileid="52" wangid="1,1,2,2,2,1,2,1"/>
   <wangtile tileid="53" wangid="2,1,1,1,2,1,2,2"/>
   <wangtile tileid="54" wangid="2,1,1,1,2,2,2,1"/>
   <wangtile tileid="55" wangid="2,1,2,1,1,1,2,2"/>
   <wangtile tileid="56" wangid="2,1,2,1,2,1,2,1"/>
   <wangtile tileid="57" wangid="2,1,2,2,2,1,1,1"/>
   <wangtile tileid="58" wangid="2,2,2,1,1,1,2,1"/>
   <wangtile tileid="59" wangid="2,2,2,1,2,1,1,1"/>
   <wangtile tileid="60" wangid="1,1,2,2,2,2,2,1"/>
   <wangtile tileid="61" wangid="2,1,1,1,2,2,2,2"/>
   <wangtile tileid="62" wangid="2,1,2,1,2,1,2,2"/>
   <wangtile tileid="63" wangid="2,1,2,1,2,2,2,1"/>
   <wangtile tileid="64" wangid="2,1,2,2,2,1,2,1"/>
   <wangtile tileid="65" wangid="2,2,2,1,1,1,2,2"/>
   <wangtile tileid="66" wangid="2,2,2,1,2,1,2,1"/>
   <wangtile tileid="67" wangid="2,2,2,2,2,1,1,1"/>
   <wangtile tileid="68" wangid="2,1,2,1,2,2,2,2"/>
   <wangtile tileid="69" wangid="2,1,2,2,2,1,2,2"/>
   <wangtile tileid="70" wangid="2,1,2,2,2,2,2,1"/>
   <wangtile tileid="71" wangid="2,2,2,1,2,1,2,2"/>
   <wangtile tileid="72" wangid="2,2,2,1,2,2,2,1"/>
   <wangtile tileid="73" wangid="2,2,2,2,2,1,2,1"/>
   <wangtile tileid="74" wangid="2,1,2,2,2,2,2,2"/>
   <wangtile tileid="75" wangid="2,2,2,1,2,2,2,2"/>
   <wangtile tileid="76" wangid="2,2,2,2,2,1,2,2"/>
   <wangtile tileid="77" wangid="2,2,2,2,2,2,2,1"/>
   <wangtile tileid="78" wangid="2,2,2,2,2,2,2,2"/>
   <wangtile tileid="1" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="2" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="3" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="4" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="5" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="6" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="7" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="8" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="9" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="10" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="11" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="15" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="17" wangid="2,2,2,2,2,2,2,2"/>
  </wangset>
  <wangset name="asphalt-sludge" type="mixed" tile="126">
   <wangcolor name="asphalt" color="#3070ff" tile="80" probability="1"/>
   <wangcolor name="sludge" color="#ff3070" tile="126" probability="1"/>
   <wangtile tileid="80" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="81" wangid="1,1,1,1,1,1,2,1"/>
   <wangtile tileid="82" wangid="1,1,1,1,2,1,1,1"/>
   <wangtile tileid="83" wangid="1,1,2,1,1,1,1,1"/>
   <wangtile tileid="84" wangid="2,1,1,1,1,1,1,1"/>
   <wangtile tileid="85" wangid="1,1,1,1,2,1,2,1"/>
   <wangtile tileid="86" wangid="1,1,2,1,1,1,2,1"/>
   <wangtile tileid="87" wangid="1,1,2,1,2,1,1,1"/>
   <wangtile tileid="88" wangid="2,1,1,1,1,1,2,1"/>
   <wangtile tileid="89" wangid="2,1,1,1,2,1,1,1"/>
   <wangtile tileid="90" wangid="2,1,2,1,1,1,1,1"/>
   <wangtile tileid="91" wangid="1,1,1,1,2,2,2,1"/>
   <wangtile tileid="92" wangid="1,1,2,1,2,1,2,1"/>
   <wangtile tileid="93" wangid="1,1,2,2,2,1,1,1"/>
   <wangtile tileid="94" wangid="2,1,1,1,1,1,2,2"/>
   <wangtile tileid="95" wangid="2,1,1,1,2,1,2,1"/>
   <wangtile tileid="96" wangid="2,1,2,1,1,1,2,1"/>
   <wangtile tileid="97" wangid="2,1,2,1,2,1,1,1"/>
   <wangtile tileid="98" wangid="2,2,2,1,1,1,1,1"/>
   <wangtile tileid="99" wangid="1,1,2,1,2,2,2,1"/>
   <wangtile tileid="100" wangid="1,1,2,2,2,1,2,1"/>
   <wangtile tileid="101" wangid="2,1,1,1,2,1,2,2"/>
   <wangtile tileid="102" wangid="2,1,1,1,2,2,2,1"/>
   <wangtile tileid="103" wangid="2,1,2,1,1,1,2,2"/>
   <wangtile tileid="104" wangid="2,1,2,1,2,1,2,1"/>
   <wangtile tileid="105" wangid="2,1,2,2,2,1,1,1"/>
   <wangtile tileid="106" wangid="2,2,2,1,1,1,2,1"/>
   <wangtile tileid="107" wangid="2,2,2,1,2,1,1,1"/>
   <wangtile tileid="108" wangid="1,1,2,2,2,2,2,1"/>
   <wangtile tileid="109" wangid="2,1,1,1,2,2,2,2"/>
   <wangtile tileid="110" wangid="2,1,2,1,2,1,2,2"/>
   <wangtile tileid="111" wangid="2,1,2,1,2,2,2,1"/>
   <wangtile tileid="112" wangid="2,1,2,2,2,1,2,1"/>
   <wangtile tileid="113" wangid="2,2,2,1,1,1,2,2"/>
   <wangtile tileid="114" wangid="2,2,2,1,2,1,2,1"/>
   <wangtile tileid="115" wangid="2,2,2,2,2,1,1,1"/>
   <wangtile tileid="116" wangid="2,1,2,1,2,2,2,2"/>
   <wangtile tileid="117" wangid="2,1,2,2,2,1,2,2"/>
   <wangtile tileid="118" wangid="2,1,2,2,2,2,2,1"/>
   <wangtile tileid="119" wangid="2,2,2,1,2,1,2,2"/>
   <wangtile tileid="120" wangid="2,2,2,1,2,2,2,1"/>
   <wangtile tileid="121" wangid="2,2,2,2,2,1,2,1"/>
   <wangtile tileid="122" wangid="2,1,2,2,2,2,2,2"/>
   <wangtile tileid="123" wangid="2,2,2,1,2,2,2,2"/>
   <wangtile tileid="124" wangid="2,2,2,2,2,1,2,2"/>
   <wangtile tileid="125" wangid="2,2,2,2,2,2,2,1"/>
   <wangtile tileid="126" wangid="2,2,2,2,2,2,2,2"/>
   <wangtile tileid="1" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="2" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="3" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="4" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="5" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="6" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="7" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="8" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="9" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="10" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="11" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="15" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="19" wangid="2,2,2,2,2,2,2,2"/>
  </wangset>
  <wangset name="asphalt-metal" type="mixed" tile="174">
   <wangcolor name="asphalt" color="#3070ff" tile="128" probability="1"/>
   <wangcolor name="metal" color="#ff3070" tile="174" probability="1"/>
   <wangtile tileid="128" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="129" wangid="1,1,1,1,1,1,2,1"/>
   <wangtile tileid="130" wangid="1,1,1,1,2,1,1,1"/>
   <wangtile tileid="131" wangid="1,1,2,1,1,1,1,1"/>
   <wangtile tileid="132" wangid="2,1,1,1,1,1,1,1"/>
   <wangtile tileid="133" wangid="1,1,1,1,2,1,2,1"/>
   <wangtile tileid="134" wangid="1,1,2,1,1,1,2,1"/>
   <wangtile tileid="135" wangid="1,1,2,1,2,1,1,1"/>
   <wangtile tileid="136" wangid="2,1,1,1,1,1,2,1"/>
   <wangtile tileid="137" wangid="2,1,1,1,2,1,1,1"/>
   <wangtile tileid="138" wangid="2,1,2,1,1,1,1,1"/>
   <wangtile tileid="139" wangid="1,1,1,1,2,2,2,1"/>
   <wangtile tileid="140" wangid="1,1,2,1,2,1,2,1"/>
   <wangtile tileid="141" wangid="1,1,2,2,2,1,1,1"/>
   <wangtile tileid="142" wangid="2,1,1,1,1,1,2,2"/>
   <wangtile tileid="143" wangid="2,1,1,1,2,1,2,1"/>
   <wangtile tileid="144" wangid="2,1,2,1,1,1,2,1"/>
   <wangtile tileid="145" wangid="2,1,2,1,2,1,1,1"/>
   <wangtile tileid="146" wangid="2,2,2,1,1,1,1,1"/>
   <wangtile tileid="147" wangid="1,1,2,1,2,2,2,1"/>
   <wangtile tileid="148" wangid="1,1,2,2,2,1,2,1"/>
   <wangtile tileid="149" wangid="2,1,1,1,2,1,2,2"/>
   <wangtile tileid="150" wangid="2,1,1,1,2,2,2,1"/>
   <wangtile tileid="151" wangid="2,1,2,1,1,1,2,2"/>
   <wangtile tileid="152" wangid="2,1,2,1,2,1,2,1"/>
   <wangtile tileid="153" wangid="2,1,2,2,2,1,1,1"/>
   <wangtile tileid="154" wangid="2,2,2,1,1,1,2,1"/>
   <wangtile tileid="155" wangid="2,2,2,1,2,1,1,1"/>
   <wangtile tileid="156" wangid="1,1,2,2,2,2,2,1"/>
   <wangtile tileid="157" wangid="2,1,1,1,2,2,2,2"/>
   <wangtile tileid="158" wangid="2,1,2,1,2,1,2,2"/>
   <wangtile tileid="159" wangid="2,1,2,1,2,2,2,1"/>
   <wangtile tileid="160" wangid="2,1,2,2,2,1,2,1"/>
   <wangtile tileid="161" wangid="2,2,2,1,1,1,2,2"/>
   <wangtile tileid="162" wangid="2,2,2,1,2,1,2,1"/>
   <wangtile tileid="163" wangid="2,2,2,2,2,1,1,1"/>
   <wangtile tileid="164" wangid="2,1,2,1,2,2,2,2"/>
   <wangtile tileid="165" wangid="2,1,2,2,2,1,2,2"/>
   <wangtile tileid="166" wangid="2,1,2,2,2,2,2,1"/>
   <wangtile tileid="167" wangid="2,2,2,1,2,1,2,2"/>
   <wangtile tileid="168" wangid="2,2,2,1,2,2,2,1"/>
   <wangtile tileid="169" wangid="2,2,2,2,2,1,2,1"/>
   <wangtile tileid="170" wangid="2,1,2,2,2,2,2,2"/>
   <wangtile tileid="171" wangid="2,2,2,1,2,2,2,2"/>
   <wangtile tileid="172" wangid="2,2,2,2,2,1,2,2"/>
   <wangtile tileid="173" wangid="2,2,2,2,2,2,2,1"/>
   <wangtile tileid="174" wangid="2,2,2,2,2,2,2,2"/>
   <wangtile tileid="1" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="2" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="3" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="4" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="5" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="6" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="7" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="8" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="9" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="10" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="11" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="15" wangid="1,1,1,1,1,1,1,1"/>
   <wangtile tileid="14" wangid="2,2,2,2,2,2,2,2"/>
   <wangtile tileid="20" wangid="2,2,2,2,2,2,2,2"/>
  </wangset>
 </wangsets>
</tileset>
