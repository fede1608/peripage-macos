import Foundation

/// The catalogs are indexed in English; this maps common Spanish searches so "gato" finds cats.
enum SpanishKeywords {
    /// Keys are folded (lowercase, no accents).
    static let map: [String: String] = [
        // Animals
        "gato": "cat", "gatito": "cat", "michi": "cat", "perro": "dog", "perrito": "dog", "cachorro": "puppy",
        "pata": "paw", "huella": "paw", "pajaro": "bird", "ave": "bird", "pez": "fish", "pescado": "fish",
        "caballo": "horse", "vaca": "cow", "cerdo": "pig", "chancho": "pig", "oveja": "sheep", "cabra": "goat",
        "conejo": "rabbit", "oso": "bear", "osito": "teddy bear", "leon": "lion", "tigre": "tiger", "mono": "monkey",
        "elefante": "elephant", "jirafa": "giraffe", "zorro": "fox", "lobo": "wolf", "raton": "mouse",
        "mariposa": "butterfly", "abeja": "bee", "arana": "spider", "hormiga": "ant", "caracol": "snail",
        "tortuga": "turtle", "serpiente": "snake", "vibora": "snake", "dinosaurio": "dinosaur", "dragon": "dragon",
        "unicornio": "unicorn", "rana": "frog", "pato": "duck", "gallina": "chicken", "pollo": "chicken",
        "buho": "owl", "lechuza": "owl", "pinguino": "penguin", "ballena": "whale", "delfin": "dolphin",
        "pulpo": "octopus", "tiburon": "shark", "animal": "animal", "animales": "animal", "mascota": "pet",
        // Nature and weather
        "flor": "flower", "rosa": "rose", "girasol": "sunflower", "tulipan": "tulip", "planta": "plant",
        "arbol": "tree", "hoja": "leaf", "cactus": "cactus", "hongo": "mushroom", "bosque": "forest",
        "sol": "sun", "luna": "moon", "estrella": "star", "nube": "cloud", "lluvia": "rain", "nieve": "snow",
        "tormenta": "storm", "rayo": "lightning", "viento": "wind", "arcoiris": "rainbow", "fuego": "fire",
        "agua": "water", "gota": "drop", "mar": "sea", "ola": "wave", "playa": "beach", "montana": "mountain",
        "isla": "island", "tierra": "earth", "mundo": "world", "planeta": "planet", "verano": "summer",
        "invierno": "winter", "otono": "autumn", "primavera": "spring", "frio": "cold", "calor": "hot",
        "naturaleza": "nature",
        // Food and drink
        "comida": "food", "fruta": "fruit", "verdura": "vegetable", "manzana": "apple", "banana": "banana",
        "frutilla": "strawberry", "fresa": "strawberry", "naranja": "orange", "limon": "lemon", "uva": "grapes",
        "sandia": "watermelon", "cereza": "cherry", "durazno": "peach", "pera": "pear", "anana": "pineapple",
        "palta": "avocado", "zanahoria": "carrot", "tomate": "tomato", "choclo": "corn", "pan": "bread",
        "queso": "cheese", "huevo": "egg", "carne": "meat", "asado": "barbecue", "hamburguesa": "hamburger",
        "pizza": "pizza", "pancho": "hot dog", "helado": "ice cream", "torta": "cake", "pastel": "cake",
        "galletita": "cookie", "galleta": "cookie", "chocolate": "chocolate", "caramelo": "candy",
        "cafe": "coffee", "taza": "mug", "cerveza": "beer", "vino": "wine", "bebida": "drink", "jugo": "juice",
        "leche": "milk", "botella": "bottle", "vaso": "glass", "cocina": "kitchen", "cocinar": "cooking",
        "cuchillo": "knife", "tenedor": "fork", "cuchara": "spoon", "plato": "plate", "desayuno": "breakfast",
        "almuerzo": "lunch", "cena": "dinner", "receta": "recipe", "mate": "mate",
        // Celebrations
        "fiesta": "party", "cumpleanos": "birthday", "cumple": "birthday", "regalo": "gift", "globo": "balloon",
        "vela": "candle", "confeti": "confetti", "navidad": "christmas", "arbolito": "christmas tree",
        "pascua": "easter", "calabaza": "pumpkin", "fantasma": "ghost", "calavera": "skull",
        "bruja": "witch", "boda": "wedding", "casamiento": "wedding", "anillo": "ring", "corona": "crown",
        "trofeo": "trophy", "medalla": "medal", "premio": "award", "celebracion": "celebration",
        // Feelings and people
        "corazon": "heart", "amor": "love", "beso": "kiss", "feliz": "happy", "alegre": "happy",
        "triste": "sad", "enojado": "angry", "risa": "laugh", "sonrisa": "smile", "cara": "face",
        "carita": "face", "llorar": "cry", "guino": "wink", "sorpresa": "surprise", "miedo": "fear",
        "persona": "person", "gente": "people", "familia": "family", "bebe": "baby", "nino": "child",
        "nina": "girl", "chico": "boy", "chica": "girl", "hombre": "man", "mujer": "woman", "mama": "mother",
        "abuela": "grandmother", "abuelo": "grandfather", "amigo": "friend", "amigos": "friends",
        "mano": "hand", "pulgar": "thumbs up", "aplauso": "clap", "ojo": "eye", "ojos": "eyes", "boca": "mouth",
        "cerebro": "brain", "hueso": "bone", "usuario": "user",
        // Things
        "casa": "house", "hogar": "home", "edificio": "building", "escuela": "school", "iglesia": "church",
        "hospital": "hospital", "tienda": "shop", "libro": "book", "cuaderno": "notebook", "lapiz": "pencil",
        "lapicera": "pen", "papel": "paper", "tijera": "scissors", "tijeras": "scissors", "regla": "ruler",
        "mochila": "backpack", "telefono": "phone", "celular": "phone", "computadora": "computer",
        "camara": "camera", "foto": "photo", "reloj": "clock", "despertador": "alarm clock",
        "calendario": "calendar", "llave": "key", "candado": "lock", "correo": "mail", "carta": "envelope",
        "sobre": "envelope", "lampara": "lamp", "bombita": "lightbulb", "foco": "lightbulb", "idea": "idea",
        "herramienta": "tool", "martillo": "hammer", "dinero": "money", "plata": "money", "moneda": "coin",
        "billete": "banknote", "compras": "shopping", "carrito": "cart", "bolsa": "bag", "ropa": "clothes",
        "remera": "t-shirt", "camisa": "shirt", "zapato": "shoe", "zapatilla": "sneaker", "sombrero": "hat",
        "gorro": "cap", "anteojos": "glasses", "lentes": "glasses", "diamante": "diamond", "joya": "jewel",
        "campana": "bell", "musica": "music", "nota": "note", "guitarra": "guitar", "auriculares": "headphones",
        "microfono": "microphone", "pelota": "ball", "futbol": "soccer", "deporte": "sport", "juego": "game",
        "dado": "dice", "carta de juego": "playing card", "rompecabezas": "puzzle", "arte": "art",
        "pintura": "paint", "pincel": "brush", "dibujo": "drawing", "paleta": "palette", "basura": "trash",
        "reciclar": "recycle", "cama": "bed", "silla": "chair", "puerta": "door", "ventana": "window",
        "bandera": "flag", "mapa": "map", "brujula": "compass", "ancla": "anchor", "paraguas": "umbrella",
        "valija": "suitcase", "maleta": "suitcase", "escoba": "broom", "vela de barco": "sailboat",
        // Transport and travel
        "auto": "car", "coche": "car", "bici": "bicycle", "bicicleta": "bicycle", "moto": "motorcycle",
        "avion": "airplane", "barco": "boat", "tren": "train", "colectivo": "bus", "micro": "bus",
        "camion": "truck", "cohete": "rocket", "viaje": "travel", "vacaciones": "vacation", "carpa": "tent",
        "camping": "camping",
        // Symbols
        "flecha": "arrow", "mas": "plus", "menos": "minus", "cruz": "cross", "tilde": "check", "ok": "check",
        "alerta": "warning", "advertencia": "warning", "peligro": "danger", "pregunta": "question",
        "informacion": "information", "lupa": "search", "buscar": "search", "configuracion": "settings",
        "ajustes": "settings", "hogar dulce hogar": "home", "numero": "number", "letra": "letter",
        "circulo": "circle", "cuadrado": "square", "triangulo": "triangle", "rayo de sol": "sun",
        "paz": "peace", "infinito": "infinity", "magia": "magic", "brillo": "sparkles", "brillos": "sparkles",
        // Colors
        "negro": "black", "blanco": "white", "rojo": "red", "azul": "blue", "verde": "green",
        "amarillo": "yellow", "violeta": "purple", "rosado": "pink", "gris": "gray", "marron": "brown",
    ]

    /// English for one Spanish word, trying simple plurals ("flores" → "flor").
    static func translate(word: String) -> String? {
        let w = word.folded
        if let hit = map[w] { return hit }
        if w.hasSuffix("es"), let hit = map[String(w.dropLast(2))] { return hit }
        if w.hasSuffix("s"), let hit = map[String(w.dropLast())] { return hit }
        return nil
    }

    static func words(_ query: String) -> [String] {
        query.folded.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
    }

    /// The query in English when at least one word was translated, otherwise nil.
    static func englishQuery(for query: String) -> String? {
        let folded = query.trimmed.folded
        if let phrase = map[folded] { return phrase == folded ? nil : phrase }
        let parts = words(query)
        var changed = false
        let english = parts.map { word -> String in
            guard let hit = translate(word: word) else { return word }
            if hit != word { changed = true }
            return hit
        }
        return changed ? english.joined(separator: " ") : nil
    }
}
