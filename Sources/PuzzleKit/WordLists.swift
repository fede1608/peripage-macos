import Foundation

public enum WordTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case animals, fruits, countries, sports, kitchen, music, jobs, nature, body, transport, school, argentina, custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .animals: "Animales"
        case .fruits: "Frutas"
        case .countries: "Países"
        case .sports: "Deportes"
        case .kitchen: "Cocina"
        case .music: "Música"
        case .jobs: "Profesiones"
        case .nature: "Naturaleza"
        case .body: "Cuerpo humano"
        case .transport: "Transporte"
        case .school: "Escuela"
        case .argentina: "Argentina"
        case .custom: "Mis palabras"
        }
    }

    /// Words as written (accents are stripped when building the grid; Ñ is kept).
    var words: [String] {
        switch self {
        case .animals:
            ["perro", "gato", "caballo", "vaca", "oveja", "conejo", "ratón", "león", "tigre", "jirafa", "elefante",
             "cebra", "mono", "oso", "lobo", "zorro", "ciervo", "ballena", "delfín", "tiburón", "pulpo", "tortuga",
             "cocodrilo", "serpiente", "águila", "búho", "loro", "pingüino", "ñandú", "carpincho", "yaguareté",
             "hormiga", "abeja", "mariposa", "caracol", "rana", "camello", "canguro", "koala", "hipopótamo",
             "rinoceronte", "murciélago", "cóndor", "puma", "guanaco", "vicuña", "llama", "foca", "gallina", "pato"]
        case .fruits:
            ["manzana", "banana", "naranja", "pera", "uva", "frutilla", "durazno", "ciruela", "cereza", "sandía",
             "melón", "kiwi", "mango", "ananá", "limón", "mandarina", "pomelo", "higo", "damasco", "frambuesa",
             "arándano", "granada", "coco", "palta", "maracuyá", "papaya", "mora", "membrillo", "guayaba",
             "níspero", "quinoto", "lima", "dátil", "pelón", "grosella", "zarzamora", "carambola", "lichi"]
        case .countries:
            ["argentina", "uruguay", "chile", "brasil", "paraguay", "bolivia", "perú", "ecuador", "colombia",
             "venezuela", "méxico", "cuba", "panamá", "españa", "francia", "italia", "alemania", "portugal",
             "grecia", "egipto", "marruecos", "japón", "china", "india", "rusia", "canadá", "australia", "noruega",
             "suecia", "irlanda", "kenia", "turquía", "corea", "vietnam", "islandia", "nicaragua", "honduras",
             "guatemala", "polonia", "austria", "suiza", "nigeria"]
        case .sports:
            ["fútbol", "tenis", "rugby", "hockey", "básquet", "vóley", "natación", "ciclismo", "atletismo",
             "boxeo", "golf", "polo", "pato", "esgrima", "remo", "surf", "judo", "karate", "ajedrez", "maratón",
             "patinaje", "esquí", "handball", "béisbol", "gimnasia", "escalada", "triatlón", "buceo", "canotaje",
             "vela", "lucha", "pádel", "taekwondo", "softbol", "skate", "senderismo"]
        case .kitchen:
            ["olla", "sartén", "cuchara", "tenedor", "cuchillo", "plato", "vaso", "taza", "horno", "hornalla",
             "heladera", "licuadora", "batidora", "colador", "rallador", "espátula", "cucharón", "fuente",
             "bandeja", "mortero", "molde", "palote", "tabla", "delantal", "receta", "harina", "azúcar", "aceite",
             "vinagre", "manteca", "huevo", "levadura", "pimienta", "orégano", "mesada", "pava", "hervir", "freír",
             "hornear", "picar", "batir", "amasar"]
        case .music:
            ["guitarra", "piano", "violín", "batería", "flauta", "trompeta", "saxo", "bajo", "arpa", "acordeón",
             "bandoneón", "charango", "tambor", "clarinete", "ukelele", "maracas", "xilófono", "melodía", "ritmo",
             "canción", "nota", "acorde", "orquesta", "coro", "banda", "partitura", "tango", "folclore", "rock",
             "cumbia", "chacarera", "zamba", "ópera", "jazz", "pentagrama", "clave", "solfeo", "tempo"]
        case .jobs:
            ["médico", "maestra", "bombero", "policía", "abogado", "arquitecto", "cocinero", "panadero",
             "carpintero", "plomero", "electricista", "enfermera", "dentista", "piloto", "periodista", "actor",
             "músico", "pintor", "escritor", "granjero", "veterinario", "ingeniero", "mecánico", "cartero",
             "jardinero", "astronauta", "fotógrafo", "peluquero", "científico", "programador", "albañil", "chofer",
             "sastre", "florista", "juez", "contador", "bibliotecaria", "guardavidas"]
        case .nature:
            ["árbol", "flor", "hoja", "río", "lago", "mar", "montaña", "volcán", "bosque", "selva", "desierto",
             "playa", "isla", "nube", "lluvia", "nieve", "viento", "sol", "luna", "estrella", "cascada", "glaciar",
             "pradera", "roca", "arena", "semilla", "raíz", "rama", "valle", "cerro", "laguna", "arcoíris",
             "trueno", "rayo", "niebla", "musgo", "helecho", "océano", "cueva", "tormenta"]
        case .body:
            ["cabeza", "ojo", "nariz", "boca", "oreja", "cuello", "hombro", "brazo", "codo", "mano", "dedo",
             "uña", "pecho", "espalda", "panza", "pierna", "rodilla", "pie", "tobillo", "talón", "corazón",
             "pulmón", "hígado", "cerebro", "hueso", "músculo", "diente", "lengua", "ceja", "pestaña", "mejilla",
             "frente", "cadera", "muñeca", "ombligo", "estómago", "riñón", "piel"]
        case .transport:
            ["auto", "colectivo", "tren", "subte", "avión", "barco", "bicicleta", "moto", "camión", "taxi",
             "helicóptero", "velero", "lancha", "globo", "cohete", "tranvía", "patineta", "monopatín",
             "submarino", "ambulancia", "tractor", "trineo", "canoa", "kayak", "carreta", "combi", "crucero",
             "remís", "ferry", "teleférico", "furgoneta", "triciclo", "carruaje", "bote"]
        case .school:
            ["lápiz", "goma", "regla", "cuaderno", "carpeta", "mochila", "pizarrón", "tiza", "maestra", "recreo",
             "aula", "libro", "tijera", "plasticola", "compás", "escuadra", "cartuchera", "sacapuntas", "birome",
             "marcador", "mapa", "tarea", "examen", "timbre", "guardapolvo", "patio", "banco", "lectura",
             "número", "dibujo", "alumno", "biblioteca", "abecedario", "globo", "acto", "boletín"]
        case .argentina:
            ["mate", "asado", "tango", "empanada", "alfajor", "gaucho", "pampa", "bombilla", "yerba", "choripán",
             "medialuna", "obelisco", "milanesa", "locro", "chimichurri", "poncho", "boleadoras", "truco",
             "potrero", "patagonia", "iguazú", "aconcagua", "ushuaia", "mendoza", "córdoba", "rosario", "salta",
             "tucumán", "provoleta", "humita", "chamamé", "malambo", "zamba", "facturas", "fernet", "dulce",
             "colectivo", "bandoneón", "glaciar"]
        case .custom:
            []
        }
    }
}

enum WordNormalizer {
    /// Uppercases, strips accents and diaeresis (Ñ survives) and drops anything that is not a letter.
    static func normalize(_ word: String) -> String {
        var out = ""
        for ch in word.uppercased() {
            switch ch {
            case "Ñ": out.append("Ñ")
            case "Á", "À", "Â", "Ä": out.append("A")
            case "É", "È", "Ê", "Ë": out.append("E")
            case "Í", "Ì", "Î", "Ï": out.append("I")
            case "Ó", "Ò", "Ô", "Ö": out.append("O")
            case "Ú", "Ù", "Û", "Ü": out.append("U")
            case "Ç": out.append("C")
            default:
                let folded = String(ch).folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es"))
                for f in folded where f.isASCII && f.isLetter { out.append(f) }
            }
        }
        return out
    }

    /// Splits user input on commas, semicolons, whitespace and new lines; normalizes and deduplicates.
    static func customWords(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for part in text.split(whereSeparator: { ",;\n\t ".contains($0) }) {
            let w = normalize(String(part))
            if w.count >= 2, seen.insert(w).inserted { out.append(w) }
        }
        return out
    }
}
