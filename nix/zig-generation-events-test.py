import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time


SCHEMA = "tiny.zig.generation/v1"
FRAME_LIMIT = 32768
STREAM_LIMIT = 64 * 1024 * 1024
FIELDS = {
    "schema",
    "phase",
    "session",
    "runner",
    "ordinal",
    "build_root",
    "request_state",
    "request_hex",
    "request_sha256",
    "epoch",
    "worktree_sha256",
    "outcome",
    "reason",
    "counts",
}
COUNT_FIELDS = {
    "total_steps",
    "succeeded_steps",
    "failed_steps",
    "dependency_failed_steps",
    "skipped_steps",
    "tests",
    "passed_tests",
    "skipped_tests",
    "failed_tests",
    "crashed_tests",
    "timed_out_tests",
}
SUCCESS = 'const std = @import("std");\npub fn main() void {}\ntest "witness" { try std.testing.expect(true); }\n'
FAILURE = 'comptime { @compileError("generation failure witness"); }\n'
# The pinned self-hosted x86_64 backend emits Mach-O test executables that
# dyld refuses or that fail at run time, so only ELF hosts select it.
SELF_HOSTED = platform.machine() == "x86_64" and sys.platform == "linux"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def attach_log(failure, log):
    failure.add_note(
        f"child stdout/stderr ({log.name}):\n"
        + log.read_text(errors="backslashreplace")
    )


def request(epoch):
    return f"{epoch}\n{'a' * 64}\n".encode()


def replace(path, data):
    temporary = path.with_suffix(path.suffix + ".next")
    temporary.write_bytes(data)
    temporary.replace(path)


def frames(path):
    data = path.read_bytes()
    require(len(data) <= STREAM_LIMIT, "stream exceeds its bound")
    result = []
    for line in data.splitlines(keepends=True):
        if not line.endswith(b"\n"):
            break
        require(len(line) <= FRAME_LIMIT, "frame exceeds its bound")
        frame = json.loads(line)
        require(set(frame) == FIELDS, "frame fields differ from the contract")
        require(frame["schema"] == SCHEMA, "wrong schema")
        if frame["counts"] is not None:
            require(set(frame["counts"]) == COUNT_FIELDS, "wrong count fields")
            require(
                all(type(n) is int and n >= 0 for n in frame["counts"].values()),
                "invalid count",
            )
        result.append(frame)
    return result


def pair(rows, epoch, outcome):
    require(len(rows) == 2, f"expected one pair: {rows}")
    begin, terminal = rows
    require(
        begin["phase"] == "begin" and terminal["phase"] == "terminal", "wrong phases"
    )
    require(
        begin["outcome"] is None and begin["counts"] is None, "begin claims a result"
    )
    require(terminal["outcome"] == outcome, "wrong terminal outcome")
    for key in FIELDS - {"phase", "outcome", "reason", "counts"}:
        require(begin[key] == terminal[key], f"capture changed at {key}")
    require(begin["epoch"] == epoch, "wrong captured epoch")
    if epoch is not None:
        require(begin["request_hex"] == request(epoch).hex(), "request bytes changed")
        require(
            begin["request_sha256"] == hashlib.sha256(request(epoch)).hexdigest(),
            "wrong request digest",
        )
    return terminal


class Witness:
    def __init__(self, zig, root, zig_lib):
        self.zig = zig
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.zig_lib = zig_lib
        self.request = self.root / "request"
        self.environment = os.environ.copy()
        for key in tuple(self.environment):
            if key.startswith("TINY_ZIG_GENERATION_"):
                del self.environment[key]
        if zig_lib:
            self.environment["ZIG_LIB_DIR"] = zig_lib
        self.results = []
        self.number = 0
        self.fixture()

    def fixture(self):
        root = self.root
        generation = str(
            Path(self.zig_lib or str(Path(self.zig).parent.parent / "lib/zig"))
            / "compiler/Maker/Generation.zig"
        )
        (root / "main.zig").write_text(SUCCESS)
        (root / "gate.py").write_text(
            "import sys\nfrom pathlib import Path\n"
            "with open('entered', 'ab') as out: out.write(b'1')\n"
            "with open('release', 'rb', buffering=0) as gate: gate.read(1)\n"
            "Path(sys.argv[2]).write_bytes(Path(sys.argv[1]).read_bytes())\n"
        )
        (root / "build.zig").write_text(
            """const std = @import("std");
pub fn build(b: *std.Build) void {
    const use_llvm = USE_LLVM;
    const blocker: ?*std.Build.Step = if (b.option(bool, "gate", "Wait for the witness request") orelse false) gate: {
        const command = b.addSystemCommand(&.{PYTHON, "gate.py"});
        command.addFileArg(b.path("main.zig"));
        _ = command.addOutputFileArg("snapshot.zig");
        break :gate &command.step;
    } else null;
    const module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = b.graph.host,
        .optimize = .debug,
    });
    const exe = b.addExecutable(.{ .name = "witness", .root_module = module, .use_llvm = use_llvm });
    const tests = b.addTest(.{ .root_module = module, .use_llvm = use_llvm });
    b.installArtifact(exe);
    if (blocker) |step| {
        exe.step.dependOn(step);
        tests.step.dependOn(step);
    }
    const test_run = b.addRunArtifact(tests);
    test_run.has_side_effects = true;
    b.default_step.dependOn(&test_run.step);
    if (b.option(bool, "nested", "Run a nested build") orelse false) {
        const nested = b.addSystemCommand(&.{ZIG, "build", "--build-file", BUILD, "--summary", "none"});
        nested.has_side_effects = true;
        b.default_step.dependOn(&nested.step);
    }
    const probe_module = b.createModule(.{
        .root_source_file = b.path("probe.zig"),
        .target = b.graph.host,
        .optimize = .debug,
    });
    probe_module.addImport("generation", b.createModule(.{
        .root_source_file = .{ .cwd_relative = GENERATION },
    }));
    const probe = b.addExecutable(.{ .name = "probe", .root_module = probe_module, .use_llvm = use_llvm });
    const installed = b.addInstallArtifact(probe, .{});
    b.step("probe", "Build the producer boundary witness").dependOn(&installed.step);
}
""".replace("USE_LLVM", "false" if SELF_HOSTED else "true")
            .replace("PYTHON", json.dumps(sys.executable))
            .replace("ZIG", json.dumps(self.zig))
            .replace("BUILD", json.dumps(str(root / "build.zig")))
            .replace("GENERATION", json.dumps(generation))
        )
        (root / "probe.zig").write_text("""const std = @import("std");
const Generation = @import("generation");
pub fn main(init: std.process.Init) void {
    const root = std.Io.Dir.cwd().openDir(init.io, ".", .{}) catch unreachable;
    defer root.close(init.io);
    var events = Generation.init(init.io, init.environ_map, root) orelse unreachable;
    defer events.deinit(init.io);
    const action = init.environ_map.get("PROBE_ACTION") orelse "partial";
    const count: u32 = if (std.mem.eql(u8, action, "capacity"))
        Generation.generation_count_max + 2 else 1;
    for (0..count) |_| {
        var captured = events.begin(init.io);
        if (std.mem.eql(u8, action, "cancelled")) {
            events.abort(init.io, &captured, error.Canceled);
        } else if (std.mem.eql(u8, action, "unknown")) {
            events.abort(init.io, &captured, error.Unexpected);
        } else events.finish(&captured, .{
            .total_steps = 0, .succeeded_steps = 0, .failed_steps = 0,
            .dependency_failed_steps = 0, .skipped_steps = 0,
            .tests = 0, .passed_tests = 0, .skipped_tests = 0,
            .failed_tests = 0, .crashed_tests = 0, .timed_out_tests = 0,
        });
        events.flush(init.io);
    }
}
""")

    def config(self, name, data=request(1)):
        self.number += 1
        stream = self.root / f"{self.number:02}-{name}.jsonl"
        stream.touch(exist_ok=False)
        stream.chmod(0o600)
        if data is None:
            self.request.unlink(missing_ok=True)
        else:
            replace(self.request, data)
        env = dict(self.environment)
        env.update(
            TINY_ZIG_GENERATION_EVENTS=str(stream),
            TINY_ZIG_GENERATION_REQUEST=str(self.request),
            TINY_ZIG_GENERATION_SESSION="b" * 64,
            TINY_ZIG_GENERATION_ROOT=str(self.root),
        )
        return stream, env

    def command(self, *args, implicit=False):
        build_file = [] if implicit else ["--build-file", str(self.root / "build.zig")]
        return [self.zig, "build", *build_file, "--summary", "all", *args]

    def run(self, name, command, env, expected=0, **kwargs):
        log = self.root / f"{name}.log"
        started = time.monotonic()
        with log.open("wb") as output:
            child = subprocess.run(
                command,
                cwd=self.root,
                env=env,
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=120,
                **kwargs,
            )
        elapsed = time.monotonic() - started
        try:
            if expected == "failure":
                require(child.returncode != 0, f"{name} unexpectedly succeeded")
            else:
                require(
                    child.returncode == expected,
                    f"{name} exited {child.returncode}: {log}",
                )
        except AssertionError as failure:
            attach_log(failure, log)
            raise
        self.results.append(
            dict(name=name, seconds=elapsed, returncode=child.returncode, log=str(log))
        )
        (self.root / "report.json").write_text(
            json.dumps(self.results, indent=2) + "\n"
        )
        return child

    def wait(self, child, predicate, label):
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if predicate():
                return
            require(child.poll() is None, f"{label}: child exited {child.returncode}")
            time.sleep(0.02)
        raise AssertionError(f"{label}: deadline exceeded")

    def stop(self, child):
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
        child.wait(timeout=10)

    def check(self):
        self.run("disabled", self.command(), self.environment)
        self.run("implicit-disabled", self.command(implicit=True), self.environment)
        require(not list(self.root.glob("*.jsonl")), "disabled build created events")
        stream, env = self.config("implicit-success")
        self.run("implicit-success", self.command(implicit=True), env)
        terminal = pair(frames(stream), 1, "success")
        require(
            terminal["build_root"] == str(self.root), "implicit root is not canonical"
        )
        require(terminal["counts"]["passed_tests"] == 1, "implicit tests are absent")
        for name, data, state in [
            ("success", request(1), "request"),
            ("idle", b"idle\n", "idle"),
            ("missing", None, "missing"),
            ("malformed", b"1\nbad\n", "malformed"),
            ("oversized", b"x" * 87, "oversized"),
            ("maximum", request(2**64 - 1), "request"),
        ]:
            stream, env = self.config(name, data)
            self.run(name, self.command(), env)
            epoch = int(data.splitlines()[0]) if state == "request" else None
            terminal = pair(frames(stream), epoch, "success")
            require(terminal["request_state"] == state, f"wrong state: {name}")
            require(terminal["counts"]["passed_tests"] == 1, "actual tests are absent")
        stream, env = self.config("unavailable")
        self.request.unlink()
        os.mkfifo(self.request, 0o600)
        self.run("unavailable", self.command(), env)
        require(
            pair(frames(stream), None, "success")["request_state"] == "unavailable",
            "non-file request was not refused",
        )
        self.request.unlink()
        stream, env = self.config("nonempty")
        stream.write_bytes(b"retained history\n")
        self.run("nonempty", self.command(), env)
        require(
            stream.read_bytes() == b"retained history\n",
            "existing event history changed",
        )
        stream, env = self.config("failed")
        replace(self.root / "main.zig", FAILURE.encode())
        self.run("failed", self.command(), env, expected="failure")
        terminal = pair(frames(stream), 1, "failed")
        require(
            terminal["counts"]["failed_steps"] > 0, "compiler failure count is absent"
        )
        stream, env = self.config("implicit-failed")
        self.run(
            "implicit-failed", self.command(implicit=True), env, expected="failure"
        )
        terminal = pair(frames(stream), 1, "failed")
        require(
            terminal["build_root"] == str(self.root),
            "implicit failure root is not canonical",
        )
        require(
            terminal["counts"]["failed_steps"] > 0,
            "implicit compiler failure count is absent",
        )
        self.run(
            "disabled-failed", self.command(), self.environment, expected="failure"
        )
        replace(self.root / "main.zig", SUCCESS.encode())
        for name, updates in [
            ("wrong-root", {"TINY_ZIG_GENERATION_ROOT": "/"}),
            ("bad-session", {"TINY_ZIG_GENERATION_SESSION": "bad"}),
        ]:
            stream, env = self.config(name)
            env.update(updates)
            self.run(name, self.command(), env)
            require(stream.stat().st_size == 0, f"{name} wrote events")
        stream, env = self.config("nested")
        self.run("nested", self.command("-Dnested=true"), env)
        pair(frames(stream), 1, "success")
        self.watch()
        self.probe()
        (self.root / "report.json").write_text(
            json.dumps(self.results, indent=2) + "\n"
        )
        print(
            json.dumps(
                {"status": "pass", "cases": len(self.results), "results": self.results}
            )
        )

    def watch(self):
        stream, env = self.config("watch")
        os.mkfifo(self.root / "release", 0o600)
        permit = os.open(self.root / "release", os.O_RDWR | os.O_NONBLOCK)
        incremental = "-fincremental" if SELF_HOSTED else "-fno-incremental"
        with (self.root / "watch.log").open("wb") as output:
            child = subprocess.Popen(
                self.command("--watch", incremental, "-Dgate=true"),
                cwd=self.root,
                env=env,
                stdout=output,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                for ordinal, epoch, outcome in [
                    (1, 1, "success"),
                    (2, 2, "failed"),
                    (3, 3, "success"),
                ]:
                    self.wait(
                        child,
                        lambda: len(frames(stream)) >= 2 * ordinal - 1,
                        "generation begin",
                    )
                    if ordinal == 1:
                        self.wait(
                            child,
                            lambda: (self.root / "entered").exists(),
                            "controlled dispatch",
                        )
                    replace(self.request, request(epoch + 1))
                    os.write(permit, b"1")
                    self.wait(
                        child,
                        lambda: len(frames(stream)) >= 2 * ordinal,
                        "generation terminal",
                    )
                    pair(frames(stream)[2 * ordinal - 2 : 2 * ordinal], epoch, outcome)
                    if ordinal < 3:
                        source = FAILURE if ordinal == 1 else SUCCESS
                        replace(self.root / "main.zig", source.encode())
                while True:
                    try:
                        if not os.read(permit, 4096):
                            break
                    except BlockingIOError:
                        break
                entered = (self.root / "entered").stat().st_size
                replace(
                    self.root / "main.zig",
                    (SUCCESS + "pub const changed = true;\n").encode(),
                )
                self.wait(
                    child,
                    lambda: len(frames(stream)) >= 7,
                    "interrupted generation begin",
                )
                self.wait(
                    child,
                    lambda: (self.root / "entered").stat().st_size > entered,
                    "interrupted dispatch",
                )
                before = stream.read_bytes()
                self.stop(child)
                require(
                    stream.read_bytes() == before,
                    "interruption manufactured a terminal frame",
                )
                rows = frames(stream)
                require(
                    len(rows) == 7 and rows[-1]["phase"] == "begin",
                    "interruption became completion",
                )
                require(
                    len({row["runner"] for row in rows}) == 1, "runner identity changed"
                )
                self.results.append(
                    dict(
                        name="resident-request-change-failure-revert-interruption",
                        frames=len(rows),
                    )
                )
            finally:
                self.stop(child)
                os.close(permit)
                if (failure := sys.exception()) is not None:
                    output.flush()
                    attach_log(failure, self.root / "watch.log")
        (self.root / "release").unlink()
        replace(self.root / "main.zig", SUCCESS.encode())

    def probe(self):
        self.run("build-probe", self.command("probe"), self.environment)
        executable = [str(self.root / "zig-out/bin/probe")]
        for action in ["cancelled", "unknown", "capacity"]:
            stream, env = self.config(action)
            env["PROBE_ACTION"] = action
            self.run(action, executable, env)
            rows = frames(stream)
            if action == "capacity":
                require(len(rows) == 8193, "generation bound lost or duplicated events")
                require(rows[-1]["phase"] == "overflow", "missing overflow event")
                require(
                    rows[-1]["reason"] == "generation_limit", "wrong overflow cause"
                )
                require(rows[-1]["ordinal"] == 4097, "wrong overflow ordinal")
            else:
                terminal = pair(rows, 1, action)
                require(
                    terminal["counts"] is None, "incomplete generation claims counts"
                )
        long_root = self.root / "long-root"
        path_limit = os.pathconf(self.root, "PC_PATH_MAX")
        for _ in range(16):
            candidate = long_root / ("\x01" * 200)
            if len(os.fsencode(candidate)) + 32 >= path_limit:
                break
            long_root = candidate
        long_root.mkdir(parents=True)
        long_stream = long_root / "events"
        long_stream.touch(exist_ok=False)
        long_request = long_root / "request"
        long_request.write_bytes(request(1))
        env = dict(self.environment)
        env.update(
            TINY_ZIG_GENERATION_EVENTS=str(long_stream),
            TINY_ZIG_GENERATION_REQUEST=str(long_request),
            TINY_ZIG_GENERATION_SESSION="b" * 64,
            TINY_ZIG_GENERATION_ROOT=str(long_root),
            PROBE_ACTION="capacity",
        )
        with (self.root / "stream-capacity.log").open("wb") as output:
            child = subprocess.run(
                executable,
                cwd=long_root,
                env=env,
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=30,
            )
        require(child.returncode == 0, "stream capacity probe failed")
        rows = frames(long_stream)
        require(rows[-1]["phase"] == "overflow", "capacity overflow is absent")
        if path_limit >= 4096:
            require(len(rows) < 8193, "stream bound was not reached")
            require(
                rows[-1]["reason"] == "stream_limit", "stream overflow reason is absent"
            )
        else:
            require(
                len(rows) == 8193 and rows[-1]["reason"] == "generation_limit",
                "short platform paths exceed the generation bound",
            )
        self.results.append(
            dict(
                name="stream-capacity",
                frames=len(rows),
                bytes=long_stream.stat().st_size,
                reason=rows[-1]["reason"],
                path_limit=path_limit,
            )
        )
        stream, env = self.config("partial")

        def limit_emission():
            signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
            resource.setrlimit(resource.RLIMIT_FSIZE, (128, 128))

        self.run("partial", executable, env, preexec_fn=limit_emission)
        data = stream.read_bytes()
        require(
            0 < len(data) <= 128 and not data.endswith(b"\n"),
            "partial emission was not retained",
        )
        require(frames(stream) == [], "partial emission became a complete frame")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("zig")
    parser.add_argument("root", type=Path)
    parser.add_argument("--zig-lib")
    args = parser.parse_args()
    Witness(args.zig, args.root, args.zig_lib).check()


if __name__ == "__main__":
    main()
