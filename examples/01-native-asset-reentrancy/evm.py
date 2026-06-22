"""Minimal pyrevm harness for the reentrancy demo.

pyrevm is a thin Python binding over revm, a Rust EVM. This module only compiles
a contract, deploys it, and exchanges calldata with it.
"""

from collections.abc import Sequence
from typing import Any

from eth_abi import decode, encode
from eth_utils import function_signature_to_4byte_selector, to_checksum_address
from pyrevm import EVM
from vyper import compile_code

UNIT = 10**18
ZERO = "0x0000000000000000000000000000000000000000"


def account(n: int) -> str:
    """Return a deterministic checksummed test address from a small integer."""
    return to_checksum_address("0x" + format(n, "040x"))


def types(signature: str) -> list[str]:
    """Read the argument types out of a signature like "mint(address,uint256)"."""
    inside = signature[signature.index("(") + 1 : signature.rindex(")")]
    return [t for t in inside.split(",") if t]


def deploy(evm: EVM, deployer: str, src_path: str, args: Sequence[Any] = ()) -> str:
    """Compile a Vyper source, deploy it, and return the new contract address.

    Constructor types come from the compiled ABI, so `args` is just the values.
    They are ABI-encoded and appended to the creation bytecode, the way Vyper
    expects them at deploy time.
    """
    with open(src_path) as f:
        out = compile_code(f.read(), output_formats=["bytecode", "abi"])
    code = bytes.fromhex(out["bytecode"][2:])

    ctor = next((e for e in out["abi"] if e.get("type") == "constructor"), None)
    if ctor:
        code += encode([a["type"] for a in ctor["inputs"]], list(args))

    return evm.deploy(deployer, code)


def call(
    evm: EVM,
    sender: str,
    to: str,
    signature: str,
    args: Sequence[Any] = (),
    value: int = 0,
) -> bytes:
    """Send a transaction from `sender` to `to`, invoking `signature` with `args`.

    The selector and argument types are taken from `signature`. Returns the raw
    output bytes.
    """
    data = function_signature_to_4byte_selector(signature)
    if args:
        data += encode(types(signature), list(args))

    return evm.message_call(sender, to, calldata=data, value=value)


def read(
    evm: EVM,
    to: str,
    signature: str,
    out_types: Sequence[str],
    args: Sequence[Any] = (),
) -> Any:
    """Call a getter and decode its return against `out_types`.

    Reads go through a throwaway caller because only the returned value matters.
    Returns the single decoded value, or a tuple when `out_types` lists several.
    """
    out = call(evm, account(0x1), to, signature, args)
    decoded = decode(list(out_types), out)

    return decoded[0] if len(decoded) == 1 else decoded
