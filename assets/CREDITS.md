# Credits

Внешние ассеты и библиотеки, использованные в проекте, с лицензиями.

Меши толпы и большинства эффектов по-прежнему строятся кодом (`KnightMesh`, `BlobMesh`, форма
террейна), но с пункта 50 в проект начали заходить готовые внешние ассеты там, где собрать
то же самое из примитивов означало бы заведомо проиграть по виду.

Каждый импорт добавляется сюда строкой: что, откуда, лицензия, где используется.

| Ассет | Источник | Лицензия | Где используется |
|---|---|---|---|
| `020_Octozilla_Art.glb` — низкополигональное существо "Octozilla" из набора Polygonal Mind "XYZ Collection" | Смоделировано студией Polygonal Mind (2018–2023), переконвертировано в GLB и переопубликовано как [ToxSam/cc0-models-Polygonal-Mind](https://github.com/ToxSam/cc0-models-Polygonal-Mind) | CC0 (без атрибуции) | Тело `Monster` (`scripts/events/monster.gd`) — выбрано за стиль (низкополигональный, плоские грани, тот же язык, что `BlobMesh`), сюжет (кайдзю-силуэт для гигантского монстра) и масштаб текстурированной модели вместо ручной сборки примитивов |
| `Fir01.fbx`, `Fir02.fbx`, `Normal_Tree01.fbx`, `Normal_Tree02.fbx`, `Dead_Tree01.fbx` — пять низкополигональных деревьев, вершинный цвет вместо текстур | [Simple Low Poly Trees](https://opengameart.org/content/simple-low-poly-trees), OpenGameArt | CC0 (без атрибуции) | `VegetationRenderer` (`scripts/rendering/vegetation_renderer.gd`) — выбраны за тот же вершинно-цветной низкополигональный язык, что уже говорят `BlobMesh`/`KnightMesh`, без единой текстуры на импорт |
| `terrain_grass.jpg`, `terrain_rock.jpg`, `terrain_sand.jpg` — PBR-фототекстуры (только альбедо-карта), 1K JPG | Grass001, Rock030, Ground080 с [ambientCG](https://ambientcg.com/) | CC0 (без атрибуции) | `terrain.gdshader` — triplanar-смешивание трёх фотографий вместо плоского вершинного цвета для рельефа острова (`World._build_terrain()`) |
| `002_Squaresquid_Art.glb` — низкополигональный "Squaresquid" из того же набора Polygonal Mind "XYZ Collection", что и Octozilla | Смоделировано студией Polygonal Mind (2018–2023), переконвертировано в GLB и переопубликовано как [ToxSam/cc0-models-Polygonal-Mind](https://github.com/ToxSam/cc0-models-Polygonal-Mind) | CC0 (без атрибуции) | Тело `Kraken` (`scripts/events/kraken.gd`) — тот же язык, что уже даёт Octozilla монстру, и уже готовый щупальцевый силуэт вместо сборки из примитивов |
