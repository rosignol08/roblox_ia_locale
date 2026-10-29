from flask import Flask, request, jsonify
import requests
import re
import threading
import uuid

app = Flask(__name__)

# Ton serveur Ollama
OLLAMA_URL = "http://127.0.0.1:11434/api/generate"

# Dictionnaire qui garde en mémoire l'état de chaque requête
memoire_taches = {}


# Cette fonction tourne en arrière-plan sans bloquer le serveur
def interroger_ollama(task_id, model_name, full_prompt):
    try:
        response = requests.post(OLLAMA_URL, json={"model": model_name, "prompt": full_prompt, "stream": False})
        response.raise_for_status()
        
        ia_text = response.json().get('response', '')
        print(f"\n REPONSE OLLAMA BRUTE\n{ia_text}")
        ia_text_clean = re.sub(r'<think>.*?</think>\s*', '', ia_text, flags=re.DOTALL)
        
        print(f"\n✅ [Tâche {task_id}] TERMINÉE ! Réponse stockée.")
        memoire_taches[task_id] = {"statut": "termine", "reponse": ia_text_clean}
    except Exception as e:
        print(f"❌ Erreur sur la tâche {task_id} : {e}")
        memoire_taches[task_id] = {"statut": "erreur", "reponse": str(e)}


@app.route('/api/agent', methods=['POST'])
def roblox_agent():
    data = request.json
    user_prompt = data.get('prompt', '')
    
    # On récupère le modèle et le mode envoyés par Roblox
    model_name = data.get('model', 'gemma4:12b')
    agent_mode = data.get('mode', 'Assistant')
    
    
    print("\n" + "="*50)
    print(" NOUVELLE REQUÊTE REÇUE DE ROBLOX !")
    print(f"Modèle ciblé : {model_name}")
    print(f"Mode actif   : {agent_mode}")
    print(f"Prompt       : {user_prompt[:1000]}...") # Affiche les 100 premiers caractères
    print("="*50 + "\n")

    # ========================================================
    # GESTION DES MODES (Les instructions cachées)
    # ========================================================
    if agent_mode == "Codeur Strict":
        system_instruction = (
            "Tu es un expert Luau pour Roblox Studio. "
            "Ne dis pas 'Bonjour' et ne donne AUCUNE explication de texte. "
            "Fournis UNIQUEMENT le code complet, optimisé et prêt à être copié-collé.\n\n"
        )
    elif agent_mode == "Débogueur":
        system_instruction = (
            "Tu es un expert en débogage Luau sur Roblox. "
            "Analyse le script fourni, trouve les erreurs ou problèmes de performances, "
            "explique pourquoi ça pose problème et donne la correction.\n\n"
        )
    elif agent_mode == "Constructeur":
        system_instruction = (
            "Tu es un Agent de construction Roblox Studio. L'utilisateur veut générer des éléments dans le jeu. "
            "Réponds UNIQUEMENT par un script Luau complet et fonctionnel entouré des balises ```lua et ```. "
            "Ce script doit utiliser Instance.new() pour créer ce que l'utilisateur demande et le parenté au workspace. "
            "Ne dis RIEN d'autre que le code.\n\n"
        )
    else: # Assistant (par défaut)
        system_instruction = "Tu es un assistant Roblox Studio. Réponds de manière concise.\n\n"
    
    full_prompt = system_instruction + user_prompt

    ollama_payload = {
        "model": model_name,
        "prompt": full_prompt,
        "stream": False
    }
    
	# Création d'un numéro de ticket unique pour Roblox
    task_id = str(uuid.uuid4())
    memoire_taches[task_id] = {"statut": "en_cours"}
	
 	# Lancement de l'IA sur un autre fil d'exécution (Thread)
    print(f"⏳ Tâche assignée à l'ID : {task_id} - Démarrage du thread...")
    print("="*50 + "\n")
    thread = threading.Thread(target=interroger_ollama, args=(task_id, model_name, full_prompt),daemon=True)
    thread.start()
    
    return jsonify({"success": True, "task_id": task_id})
    
# Nouvelle route utilisée par Roblox pour vérifier si c'est fini
@app.route('/api/status/<task_id>', methods=['GET'])
def check_status(task_id):
    tache = memoire_taches.get(task_id)
    if not tache:
        return jsonify({"statut": "inconnu"}), 404
    return jsonify(tache)

@app.route('/api/cancel/<task_id>', methods=['POST'])
def cancel_task(task_id):
    if task_id in memoire_taches:
        memoire_taches[task_id]['statut'] = "annule"
        print(f"🛑 Tâche {task_id} marquée comme annulée par Roblox.")
        return jsonify({"success": True})
    return jsonify({"success": False})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
