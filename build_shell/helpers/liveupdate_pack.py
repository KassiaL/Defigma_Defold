import argparse
import hashlib
import json
import math
import os
import time
import zipfile

import liveupdate_ddf_pb2

STANDALONE_UNIT_SIZE = 4194304
MIN_ARCHIVE_SIZE = 1572864
TARGET_ARCHIVE_SIZE = 3145728
MAX_ARCHIVE_SIZE = 7340032
BOUNDARY_MASK_BEFORE_TARGET = 0x07
BOUNDARY_MASK_AFTER_TARGET = 0x01
HASH_LEN = 16
NAME_HASH_LEN = 8
ZIP_ENTRY_DATE_TIME = (1980, 1, 1, 0, 0, 0)
ZIP_ENTRY_EXTERNAL_ATTR = 0o100644 << 16
TEXTURE_SUFFIX = "_texture"


class PackContext:
    def __init__(self, graph_path, resources_folder, result_folder):
        self.graph_path = graph_path
        self.resources_folder = resources_folder
        self.result_folder = result_folder
        self.dmanifest_name = "liveupdate.game.dmanifest"
        self.dmanifest_path = os.path.join(self.resources_folder, self.dmanifest_name)
        self.extension_archive = ".arcd0"
        self.current_timestamp = str(math.floor(time.time()))
        self.temp_suffix = self.current_timestamp

        self.added_files = {}
        self.created_archives = {}

        self.dmanifest = None
        self.dmanifest_data = None
        self.files = {}
        self.excluded_proxies = {}
        self.zip_files = {}
        self.common_files = {}
        self.manifest_data_resources = {}
        self.dependency_list = {}

    def get_file_size(self, hex_digest):
        full_path = os.path.join(self.resources_folder, hex_digest)
        if os.path.exists(full_path):
            return os.path.getsize(full_path)

    def load_json_file(self, file_path):
        try:
            with open(file_path, "r") as file:
                return json.load(file)
        except (FileNotFoundError, json.JSONDecodeError) as e:
            raise Exception(f"Error loading JSON from {file_path}: {e}")

    def parse_protobuf_file(self, file_path, proto_class):
        try:
            with open(file_path, "rb") as file:
                proto_instance = proto_class()
                proto_instance.ParseFromString(file.read())
                return proto_instance
        except FileNotFoundError:
            raise Exception(f"Protobuf file not found: {file_path}")
        except Exception as e:
            raise Exception(f"Error parsing protobuf file {file_path}: {e}")

    def precheck_all_files_for_list(self, files_list):
        missing_files = []
        for filepath in files_list:
            file_info = self.files.get(filepath)
            if not file_info:
                print(f"Warning: No file info for {filepath}")
                continue
            if not file_info.get("hexDigest"):
                missing_files.append(filepath)
        if missing_files:
            print("\nFiles missing hexDigest:")
            header = "{:<6} {:<30} {:<}".format("No.", "Reason", "Path")
            print(header)
            print("-" * len(header))
            for i, path in enumerate(missing_files, start=1):
                print("{:<6} {:<30} {:<}".format(i, "Missing hexDigest", path))
            raise Exception("Found files missing hexDigest, build aborted.")

    def precheck_duplicate_digests(self):
        """Two resource paths whose compiled content is byte identical share one hexDigest. Defold
        stores the bytes once, which is fine, but it almost always means a mistake in the project --
        a copy-pasted .font left pointing at the other ttf, say -- and it used to cost one of the
        two paths its manifest entry, which is a RESOURCE_NOT_FOUND at runtime. Only resources that
        actually travel in the archives are checked; the main bundle resolves its own duplicates."""
        duplicates = {
            hex_digest: sorted(entry.url for entry in entries)
            for hex_digest, entries in self.manifest_data_resources.items()
            if len(entries) > 1 and os.path.exists(os.path.join(self.resources_folder, hex_digest))
        }
        if not duplicates:
            return
        print("\nResources with identical content:")
        header = "{:<6} {:<18} {:<}".format("No.", "Digest", "Paths")
        print(header)
        print("-" * len(header))
        for index, (hex_digest, urls) in enumerate(sorted(duplicates.items()), start=1):
            print("{:<6} {:<18} {:<}".format(index, hex_digest[:16], ", ".join(urls)))
        raise Exception("Found resources with identical content, build aborted.")

    def add_files_to_zip(self, zip_file, files_list, zip_name):
        """Two resource paths with identical content share one hexDigest, so the bytes are stored
        once but every url pointing at them has to be registered: an entry left out here is a
        RESOURCE_NOT_FOUND at runtime for that path."""
        for filepath in files_list:
            file_info = self.files[filepath]
            hex_digest = file_info["hexDigest"]
            if hex_digest in self.added_files:
                continue
            file_path_hex = os.path.join(self.resources_folder, hex_digest)
            with open(file_path_hex, "rb") as file_obj:
                self.write_zip_bytes(zip_file, hex_digest, file_obj.read())
            self.added_files[hex_digest] = zip_name
            self.dmanifest_data.resources.extend(self.manifest_data_resources[hex_digest])

    def create_zip_info(self, arcname):
        zip_info = zipfile.ZipInfo(arcname)
        zip_info.date_time = ZIP_ENTRY_DATE_TIME
        zip_info.compress_type = zipfile.ZIP_DEFLATED
        zip_info.create_system = 3
        zip_info.external_attr = ZIP_ENTRY_EXTERNAL_ATTR
        return zip_info

    def write_zip_bytes(self, zip_file, arcname, data):
        zip_file.writestr(self.create_zip_info(arcname), data)

    def compute_archive_identity_from_files(self, files_list):
        """Identity depends on resource content only, so build settings that do not change
        the resources (variant, dmanifest urls, excluded extensions) keep archive versions stable."""
        hasher = hashlib.sha256()
        for hex_digest in sorted(self.files[filepath]["hexDigest"] for filepath in files_list):
            hasher.update(hex_digest.encode("utf-8"))
            with open(os.path.join(self.resources_folder, hex_digest), "rb") as file_obj:
                hasher.update(file_obj.read())
        return hasher.hexdigest()

    def create_zip_archive(self, archive_name, files_list):
        temp_name = archive_name + self.temp_suffix
        zip_path = os.path.join(self.result_folder, temp_name + self.extension_archive)
        archive_identity = self.compute_archive_identity_from_files(files_list)
        version_hash = self.truncate_hash(archive_identity)
        self.dmanifest_data.ClearField("resources")
        print(f"Creating archive: {archive_name}{self.extension_archive}")
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zip_file:
            self.add_files_to_zip(zip_file, files_list, temp_name)

            archive_dmanifest = liveupdate_ddf_pb2.ManifestFile()
            archive_dmanifest.CopyFrom(self.dmanifest)
            archive_dmanifest.data = self.dmanifest_data.SerializeToString()
            archive_dmanifest.archive_identifier = bytes.fromhex(archive_identity[:32])
            self.write_zip_bytes(zip_file, self.dmanifest_name, archive_dmanifest.SerializeToString())
        self.created_archives[archive_name] = {
            "path": zip_path,
            "version_hash": version_hash,
            "archive_size": os.path.getsize(zip_path),
        }

    def get_deps_files(self, path, child_path=None):
        if child_path is None:
            self.zip_files[path] = {}
        else:
            self.zip_files[path][child_path] = self.files[child_path]

        search_path = path if child_path is None else child_path
        if "children" in self.files[search_path]:
            for child in self.files[search_path]["children"]:
                if not self.files[child]["isInMainBundle"]:
                    if self.files[child].get("nodeType") != "ExcludedCollectionProxy":
                        self.get_deps_files(path, child)
                    else:
                        self.zip_files[path][child] = self.files[child]

    def load_inputs(self):
        self.dmanifest = self.parse_protobuf_file(self.dmanifest_path, liveupdate_ddf_pb2.ManifestFile)
        self.dmanifest_data = liveupdate_ddf_pb2.ManifestData()
        self.dmanifest_data.ParseFromString(self.dmanifest.data)

        self.manifest_data_resources = {}
        for resource in self.dmanifest_data.resources:
            self.manifest_data_resources.setdefault(resource.hash.data.hex(), []).append(resource)

        for element in self.load_json_file(self.graph_path):
            hex_digest = element.get("hexDigest")
            if hex_digest:
                element["size"] = self.get_file_size(hex_digest)
            self.files[element["path"]] = element
            if element.get("nodeType") == "ExcludedCollectionProxy":
                self.excluded_proxies[element["path"]] = element

    def build_common_files(self):
        for path in self.zip_files:
            main_file = self.files[path]["children"][0]
            for res_name in self.zip_files[path]:
                info = self.common_files.setdefault(res_name, {"name": res_name, "files": [], "use_count": 0})
                if main_file not in info["files"]:
                    info["use_count"] += 1
                    info["files"].append(main_file)

    def precheck_files(self):
        all_file_paths = set(self.common_files.keys())
        for path in self.zip_files:
            all_file_paths.update(self.zip_files[path].keys())
        self.precheck_all_files_for_list(sorted(all_file_paths))

    def build_units(self, file_keys):
        """A texture and its texture set always travel together, so they never split across archives."""
        key_index = {key: index for index, key in enumerate(file_keys)}
        key_set = set(file_keys)
        used = set()

        def pair_name(key):
            if key.endswith(".texturec"):
                return key[: -len(".texturec")] + ".a.texturesetc"
            if key.endswith(".a.texturesetc"):
                return key[: -len(".a.texturesetc")] + ".texturec"
            return None

        units = []
        for key in file_keys:
            if key in used:
                continue
            used.add(key)
            keys = [key]
            pair = pair_name(key)
            if pair in key_set and pair not in used:
                used.add(pair)
                keys = [key, pair] if key_index[key] < key_index[pair] else [pair, key]
            units.append(
                {
                    "keys": keys,
                    "size": sum(self.files[member]["size"] for member in keys),
                    "digest": self.files[keys[-1]]["hexDigest"],
                }
            )
        return units

    def is_chunk_boundary(self, digest, size):
        """Content defined boundary: where an archive ends is decided by the content of the resource
        that ends it, not by the accumulated size, so inserting or removing a resource
        rewrites a single archive instead of shifting every archive after it."""
        if size < MIN_ARCHIVE_SIZE:
            return False
        if size >= MAX_ARCHIVE_SIZE:
            return True
        mask = BOUNDARY_MASK_AFTER_TARGET if size >= TARGET_ARCHIVE_SIZE else BOUNDARY_MASK_BEFORE_TARGET
        return int(digest[:8], 16) & mask == 0

    def split_into_chunks(self, file_keys):
        chunks = []
        current = []
        size = 0
        for unit in self.build_units(file_keys):
            if unit["size"] >= STANDALONE_UNIT_SIZE:
                if current:
                    chunks.append(current)
                    current = []
                    size = 0
                chunks.append(unit["keys"])
                continue
            current.extend(unit["keys"])
            size += unit["size"]
            if self.is_chunk_boundary(unit["digest"], size):
                chunks.append(current)
                current = []
                size = 0
        if current:
            chunks.append(current)
        return chunks

    def chunk_name(self, base_name, chunk):
        """Named after the first resource in the chunk: the name survives content changes,
        so the client replaces the archive in place instead of downloading a new one."""
        name_hash = hashlib.sha256(chunk[0].encode("utf-8")).hexdigest()[:NAME_HASH_LEN]
        return f"{base_name}_{name_hash}"

    def is_texture_resource(self, resource_path):
        return resource_path.endswith(".texturec") or resource_path.endswith(".a.texturesetc")

    def truncate_hash(self, hex_digest):
        return hex_digest[:HASH_LEN]

    def add_dependency(self, main_file, archive_name):
        archives = self.dependency_list.setdefault(main_file, [])
        if archive_name not in archives:
            archives.append(archive_name)

    def create_common_archives_by_dependency_sets(self):
        groups = {}
        for res_name, info in self.common_files.items():
            if info["use_count"] <= 1:
                continue
            key = tuple(sorted(info["files"]))
            group = groups.setdefault(key, {"textures": [], "others": []})
            if self.is_texture_resource(res_name):
                group["textures"].append(res_name)
            else:
                group["others"].append(res_name)

        for key in sorted(groups.keys()):
            for kind, prefix in (("others", "common"), ("textures", "common_texture")):
                for chunk in self.split_into_chunks(sorted(groups[key][kind])):
                    archive_name = self.chunk_name(prefix, chunk)
                    self.create_zip_archive(archive_name, chunk)
                    for main_file in key:
                        self.add_dependency(main_file, archive_name)

    def create_collection_chunks(self, base_name, primary_name, main_file, files_list):
        for index, chunk in enumerate(self.split_into_chunks(files_list)):
            archive_name = primary_name if index == 0 and base_name == primary_name else self.chunk_name(base_name, chunk)
            self.create_zip_archive(archive_name, chunk)
            if archive_name != primary_name:
                self.add_dependency(main_file, archive_name)

    def create_collection_archives(self):
        print("Starting zip file collection")
        for path in sorted(self.zip_files.keys()):
            main_file = self.files[path]["children"][0]
            collection_name = os.path.splitext(os.path.basename(main_file))[0]
            own_files = [
                res_name
                for res_name in sorted(self.zip_files[path].keys())
                if self.common_files[res_name]["use_count"] <= 1
            ]
            texture_files = [f for f in own_files if self.is_texture_resource(f)]
            other_files = [f for f in own_files if not self.is_texture_resource(f)]

            self.create_collection_chunks(collection_name, collection_name, main_file, other_files)
            self.create_collection_chunks(
                collection_name + TEXTURE_SUFFIX, collection_name, main_file, texture_files
            )
        print("Zip file collection completed.")

    def build_manifest_output(self):
        collections_list = []
        collection_index = {}

        def intern_collection(name):
            idx = collection_index.get(name)
            if idx is None:
                idx = len(collections_list)
                collection_index[name] = idx
                collections_list.append(name)
            return idx

        archive_deps = {}
        for filepath, archives in self.dependency_list.items():
            file_name = os.path.splitext(os.path.basename(filepath))[0]
            for archive in archives:
                archive_deps.setdefault(archive, []).append(file_name)

        files = {}
        for archive_name, archive_info in self.created_archives.items():
            version_hash = archive_info["version_hash"]
            dep_files = archive_deps.get(archive_name)
            if dep_files:
                files[archive_name] = [version_hash, [intern_collection(f) for f in sorted(dep_files)]]
            else:
                files[archive_name] = [version_hash]

        return {
            "version": self.current_timestamp,
            "collections": collections_list,
            "files": files,
        }

    def rename_archives_to_version(self):
        for archive_name, archive_info in self.created_archives.items():
            final_name = archive_name + "_" + archive_info["version_hash"] + self.extension_archive
            final_path = os.path.join(self.result_folder, final_name)
            os.replace(archive_info["path"], final_path)
            archive_info["path"] = final_path
            print(f"Final archive: {final_name}")

    def write_outputs(self):
        with open(os.path.join(self.result_folder, "manifest.json"), "w") as outfile:
            json.dump(self.build_manifest_output(), outfile, indent=4)

        archive_sizes = {
            "files": {name: info["archive_size"] for name, info in self.created_archives.items()}
        }
        with open(os.path.join(self.result_folder, "archive_sizes.json"), "w") as outfile:
            json.dump(archive_sizes, outfile, indent=4)

    def run(self):
        self.load_inputs()
        self.precheck_duplicate_digests()

        for proxy_path in self.excluded_proxies:
            self.get_deps_files(proxy_path)

        os.makedirs(self.result_folder, exist_ok=True)

        self.build_common_files()
        self.precheck_files()

        self.create_common_archives_by_dependency_sets()
        self.create_collection_archives()

        self.rename_archives_to_version()
        self.write_outputs()

        print("Process completed successfully.")


def main():
    parser = argparse.ArgumentParser(description="Pack Defold liveupdate resources into versioned archives")
    parser.add_argument("--graph", default="build/default/game.graph.json")
    parser.add_argument("--resources", default="liveupdate_dist")
    parser.add_argument("--output", default="liveupdate_zip")
    args = parser.parse_args()
    PackContext(args.graph, args.resources, args.output).run()


if __name__ == "__main__":
    main()
