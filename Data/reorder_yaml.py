import sys
import re
from pathlib import Path
import yaml

def get_key_order(directory_name):
    char_order = ["player", "leader", "ninten", "ana", "lloyd", "teddy", "pippi", "Ninten", "Ana", "Lloyd", "Teddy", "Pippi", "chkninten", "chkana", "chklloyd", "chkteddy", "chkpippi"]
    

    # talkeremote
    key_orders = {
        "Dialogue": ["actors", "talker", "name", "sound", "talkeremote", "text", "options", "showbox", "cleardialogue", "item", "removeitem", "cash", "givecash", "actorsdir", "actorsemote", "actorsjump", "actorsmove", "actorsturn",  "teleportactors", "teleportparty", "x", "y", "movement", "speed", "height", "length", "animation", "type", "movecam", "changecam", "returncam", "musicvolume", "soundeffect", "fadein", "fadefocus", "fadeout", "objectfunction", "setflags", "unsetflags", "heal", "cure", "restorepp", "setpartymembers", "changereplaced", "open_storage", "open_shop", "battlers", "winflag",  "wait", "autoadvance", "caninput", "if", "hasitem", "hasinstorage", "hascash", "invspace", "leader", "haspartymembers", "partysize", "hasstatus", "flags", "goto"],
        "battlerss": ["name", "nickname", "description", "article", "maxhp", "hp", "maxpp", "pp", "offense", "defense", "speed", "iq", "guts", "level", "exp", "cash", "items", "item", "chance", "skills", "swan_song", "battlescript", "skill", "weight", "boss", "sprite", "music", "bg", "ov", "anim", "spriteOffset", "shadow", "connections", "returning", "maxDistance", "maxSpeed", "acceleration", "friction", "walkFrequency"],
        "BattleScripts": ["if", "hp", "turns", "do_skill", "text", "sound", "goto", "die"],
        "BattleSkills": ["name", "level", "description", "article", "dialog", "skill_type", "action_type", "use_cases", "psi_category", "damage_type", "target_type", "target_unconscious", "target_incapacitated", "damage_or_heal", "variance", "priority", "status_effects", "status_heals", "status_amount_healed", "stat_mods", "offense", "defense", "speed", "iq", "guts", "allies", "miss_chance", "fail_dialog", "pp_cost", "hp_cost", "hit_effect", "pre_hit_effect", "screen_effect", "enemy_screen_effect", "user_anim", "user_anim_colors", "user_hide_anim", "enemy_flash_color", "use_sound", "hit_sound"],
        "FieldSkills": ["name", "description", "flag", "usable"],
        "Items": ["name", "short_name", "description", "article", "keyitem", "doses", "cost", "value", "can_use", "can_consume", "actions", "function", "text", "battle_action", "passive_skills", "transform", "slot", "status_heals", "HPrecover", "PPrecover", "boost", "affinity_multipliers", "maxhp", "hp", "maxpp", "pp", "offense", "defense", "speed", "iq", "guts"],
        "StatusAilments": ["healing", "messages", "ignore_reinflict", "hidden", "exclusive_status", "status_bubble", "effects_by_char"]
    }
    
    return key_orders.get(directory_name, []) + char_order

def reorder_dict(data, key_order):
    if not isinstance(data, dict):
        return data
    
    ordered_data = {key: reorder_dict(data[key], key_order) for key in key_order if key in data}
    unordered_data = {key: reorder_dict(data[key], key_order) for key in data if key not in key_order}
    ordered_data.update(unordered_data)
    
    return ordered_data

def get_root_category(yaml_file, root_directory):
    try:
        relative_path = yaml_file.relative_to(root_directory)
        return relative_path.parts[0] if len(relative_path.parts) > 0 else ""
    except ValueError:
        return ""

def quoted_presenter(dumper, data):
    if isinstance(data, str) and re.fullmatch(r"[A-Fa-f0-9]{6}", data):
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style="'")
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)

def reorder_yaml_keys(yaml_file, root_directory):
    try:
        with open(yaml_file, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
    except Exception as e:
        print(f"Skipping {yaml_file}: Error reading file - {e}")
        return
    
    if not isinstance(data, dict):
        print(f"Skipping {yaml_file}: not a dictionary.")
        return
    
    directory_name = get_root_category(yaml_file, root_directory)
    key_order = get_key_order(directory_name)
    ordered_data = reorder_dict(data, key_order) if key_order else data
    
    yaml.add_representer(str, quoted_presenter)
    
    try:
        with open(yaml_file, 'w', encoding='utf-8') as f:
            yaml.dump(ordered_data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    except Exception as e:
        print(f"Error writing file {yaml_file}: {e}")

def process_directory(directory):
    directory = Path(directory).resolve()
    if not directory.exists() or not directory.is_dir():
        print(f"Invalid directory: {directory}")
        sys.exit(1)
    
    for yaml_file in directory.rglob("*.yaml"):
        print(f"Processing {yaml_file}...")
        reorder_yaml_keys(yaml_file, directory)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <directory>")
        sys.exit(1)
    
    directory = sys.argv[1]
    process_directory(directory)