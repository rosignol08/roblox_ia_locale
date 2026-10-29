# Décisions d'architecture et plan d'exécution

## Plan initial

### P0 - Bugs critiques (priorité immédiate)
1. **Affichage tronqué** : Découper les réponses longues en plusieurs TextBox (≤8000 chars)
2. **Texte non copiable** : Remplacer TextLabel par TextBox non-éditable + boutons d'action
3. **Injection dans script existant** : Améliorer la détection et le ciblage
4. **extractCode** : Gérer tous les formats de blocs de code
5. **Ordre des fonctions** : Réorganiser pour éviter les nil
6. **Instance.new + Source** : Utiliser write_script au lieu de code exécuté
7. **Serveur robuste** : Timeouts, annulation réelle, num_ctx/num_predict

### P1 - Boucle d'agent avec outils
- Implémenter le protocole d'outils JSON
- Outils de lecture (get_selection, get_tree, read_script, etc.)
- Outils d'écriture (create_instance, write_script, etc.)
- Serveur /api/chat avec historique et streaming

### P2 - Interface améliorée
- Vue chat avec bulles
- Réglages persistants
- Contexte automatique
- Auto-correction

### P3 - Polish et documentation
- Tests complets
- Documentation utilisateur
- KNOWN_LIMITS.md

## Décisions techniques

1. **Un seul fichier plugin** : Garder OllamaAssistant.lua unique pour simplicité d'installation
2. **Protocole d'outils JSON** : Format robuste indépendant du modèle Ollama
3. **Sérialisation typée** : Format JSON pour les valeurs Roblox (Vector3, Color3, etc.)
4. **Waypoints ChangeHistory** : Toutes les écritures sous waypoint pour annulation fiable
5. **Timeouts non-bloquants** : task.wait() régulier pour ne pas geler Studio

## Risques identifiés

- API ScriptEditorService peut varier entre versions de Studio
- Limites de caractères des éléments UI Roblox
- Compatibilité avec différents modèles Ollama
- Performance avec de gros workspaces
