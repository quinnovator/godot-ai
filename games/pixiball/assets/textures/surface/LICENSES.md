# Surface detail textures

All maps in this directory are CC0 (public domain) photogrammetry textures
from [Poly Haven](https://polyhaven.com) (license:
https://polyhaven.com/license), downloaded at 1K JPG resolution:

| Files | Poly Haven asset |
| --- | --- |
| `cotton_jersey_nor_gl_1k.jpg`, `cotton_jersey_rough_1k.jpg` | [cotton_jersey](https://polyhaven.com/a/cotton_jersey) |
| `brown_leather_nor_gl_1k.jpg`, `brown_leather_rough_1k.jpg` | [brown_leather](https://polyhaven.com/a/brown_leather) |
| `fine_grained_wood_nor_gl_1k.jpg`, `fine_grained_wood_rough_1k.jpg` | [fine_grained_wood](https://polyhaven.com/a/fine_grained_wood) |

They are sampled triplanar by the ballplayer's runtime surface shader
(`characters/ballplayer_actor.gd`) as micro-surface detail (normal +
roughness); no albedo data is used, so team recoloring is unaffected.
