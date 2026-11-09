import Foundation
import SwiftUI

// MARK: - Le viste degli ologrammi della tavola (build 11.0 (19), 9 nov)
// Sull'iPhone: la tela grande con le chip delle prove (ProveOloVista), in testa alla sezione come nel mockup. Sul polso: la prova
// scelta sull'iPhone, in piccolo e senza scritte (ProvaOloPiccola), come Diario, Sonno, Briefing, Spesa, Serata e Bea.

struct OlogrammaMeteoProve: View {
    let dati: DatiMeteoOlo
    var piccolo = false
    @State private var prove = ProveMeteo()

    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .meteo) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .meteo, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
            #endif
        }
    }
}

struct OlogrammaCuorePiccolo: View {
    let dati: DatiCuoreOlo
    @State private var prove = ProveCuore()
    var body: some View {
        ProvaOloPiccola(sezione: .cuore) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
    }
}

#if os(iOS)
struct OlogrammaEdithProve: View {
    let dati: DatiEdithOlo
    @State private var prove = ProveEdith()
    var body: some View {
        ProveOloVista(sezione: .edith, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
    }
}
#endif

struct OlogrammaVitalsProve: View {
    let dati: DatiVitalsOlo
    var piccolo = false
    @State private var prove = ProveVitals()
    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .vitals) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .vitals, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
            #endif
        }
    }
}

struct OlogrammaGithubProve: View {
    let dati: DatiGithubOlo
    var piccolo = false
    @State private var prove = ProveGithub()
    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .github) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .github, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
            #endif
        }
    }
}

struct OlogrammaSupabaseProve: View {
    let dati: DatiSupabaseOlo
    var piccolo = false
    @State private var prove = ProveSupabase()
    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .supabase) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .supabase, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
            #endif
        }
    }
}

struct OlogrammaArchivioProve: View {
    let dati: DatiArchivioOlo
    var piccolo = false
    @State private var prove = ProveArchivio()
    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .archivio) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .archivio, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
            #endif
        }
    }
}

struct OlogrammaCostiProve: View {
    let dati: DatiCostiOlo
    var piccolo = false
    @State private var prove = ProveCosti()
    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .costi) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .costi, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
            #endif
        }
    }
}
