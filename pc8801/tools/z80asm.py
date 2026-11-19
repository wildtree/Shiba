#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
z80asm.py - 自作 Z80 アセンブラ (PC-8801 柴犬陣取り移植用)

外部依存なし。Python 3.8+ で動く。

書式
----
    [ラベル[:]]  [ニーモニック [オペランド,...]]   ; コメント

    ラベル        英字/_ で始まる識別子。先頭が '.' のものはローカルラベル
                  (直前のグローバルラベルの中だけで有効)
    数値          10進 / 0x1F / 1FH / 0b1010 / %1010 / 'A'
    $             現在のアドレス (PC)
    演算子        + - * / % & | ^ << >> ~ ( ) 単項-

疑似命令
--------
    ORG   addr              出力アドレスを設定
    EQU   expr              (ラベルと一緒に) 定数定義
    DB/DEFB  v,...          バイト列 ("文字列" も可)
    DW/DEFW  v,...          ワード列 (リトルエンディアン)
    DS/DEFS  n[,fill]       n バイト埋める
    ALIGN n                 n バイト境界まで埋める
    INCLUDE "file"          ファイルを取り込む
    ASSERT expr[,"msg"]     アセンブル時の検査
    END                     以降を無視
"""

import os
import re
import sys

# --------------------------------------------------------------------------
# レジスタ等のエンコード表
# --------------------------------------------------------------------------

R8 = {'B': 0, 'C': 1, 'D': 2, 'E': 3, 'H': 4, 'L': 5, 'A': 7}
RP = {'BC': 0, 'DE': 1, 'HL': 2, 'SP': 3}
RP_PUSH = {'BC': 0, 'DE': 1, 'HL': 2, 'AF': 3}
CC = {'NZ': 0, 'Z': 1, 'NC': 2, 'C': 3, 'PO': 4, 'PE': 5, 'P': 6, 'M': 7}
ALU = {'ADD': 0, 'ADC': 1, 'SUB': 2, 'SBC': 3, 'AND': 4, 'XOR': 5, 'OR': 6, 'CP': 7}
ROT = {'RLC': 0, 'RRC': 1, 'RL': 2, 'RR': 3, 'SLA': 4, 'SRA': 5, 'SLL': 6, 'SRL': 7}

# 引数なし命令
SIMPLE = {
    'NOP': [0x00], 'RLCA': [0x07], 'RRCA': [0x0F], 'RLA': [0x17], 'RRA': [0x1F],
    'DAA': [0x27], 'CPL': [0x2F], 'SCF': [0x37], 'CCF': [0x3F],
    'HALT': [0x76], 'DI': [0xF3], 'EI': [0xFB], 'EXX': [0xD9],
    'RET': [0xC9], 'NEG': [0xED, 0x44], 'RETN': [0xED, 0x45], 'RETI': [0xED, 0x4D],
    'RRD': [0xED, 0x67], 'RLD': [0xED, 0x6F],
    'LDI': [0xED, 0xA0], 'CPI': [0xED, 0xA1], 'INI': [0xED, 0xA2], 'OUTI': [0xED, 0xA3],
    'LDD': [0xED, 0xA8], 'CPD': [0xED, 0xA9], 'IND': [0xED, 0xAA], 'OUTD': [0xED, 0xAB],
    'LDIR': [0xED, 0xB0], 'CPIR': [0xED, 0xB1], 'INIR': [0xED, 0xB2], 'OTIR': [0xED, 0xB3],
    'LDDR': [0xED, 0xB8], 'CPDR': [0xED, 0xB9], 'INDR': [0xED, 0xBA], 'OTDR': [0xED, 0xBB],
}


class AsmError(Exception):
    pass


# --------------------------------------------------------------------------
# 式の評価
# --------------------------------------------------------------------------

TOKEN_RE = re.compile(r"""
      (?P<ws>\s+)
    | (?P<chr>'(?:\\.|[^'])')
    | (?P<hex1>0[xX][0-9a-fA-F]+)
    | (?P<bin1>0[bB][01]+)
    | (?P<bin2>%[01]+)
    | (?P<hex2>[0-9][0-9a-fA-F]*[hH])
    | (?P<num>[0-9]+)
    | (?P<pc>\$)
    | (?P<id>[A-Za-z_.][A-Za-z_.0-9]*)
    | (?P<op><<|>>|<=|>=|==|!=|&&|\|\||[-+*/%&|^~()<>!])
""", re.VERBOSE)


def tokenize_expr(s):
    toks = []
    i = 0
    while i < len(s):
        m = TOKEN_RE.match(s, i)
        if not m:
            raise AsmError("式が解釈できません: %r" % s[i:])
        i = m.end()
        kind = m.lastgroup
        text = m.group()
        if kind == 'ws':
            continue
        toks.append((kind, text))
    return toks


def unescape_char(text):
    body = text[1:-1]
    if body.startswith('\\'):
        return {'n': 10, 'r': 13, 't': 9, '0': 0, '\\': 92, "'": 39, '"': 34}[body[1]]
    return ord(body)


class ExprParser:
    """優先順位付き再帰下降パーサ。"""

    # 低い方が先に結合をやめる
    LEVELS = [
        ('||',), ('&&',),
        ('==', '!='), ('<', '>', '<=', '>='),
        ('|',), ('^',), ('&',), ('<<', '>>'), ('+', '-'), ('*', '/', '%'),
    ]

    def __init__(self, toks, resolve, pc):
        self.toks = toks
        self.pos = 0
        self.resolve = resolve
        self.pc = pc

    def peek(self):
        return self.toks[self.pos] if self.pos < len(self.toks) else (None, None)

    def take(self):
        t = self.peek()
        self.pos += 1
        return t

    def parse(self):
        v = self.level(0)
        if self.pos != len(self.toks):
            raise AsmError("式の末尾が余っています: %r" % (self.toks[self.pos:],))
        return v

    def level(self, n):
        if n >= len(self.LEVELS):
            return self.unary()
        ops = self.LEVELS[n]
        v = self.level(n + 1)
        while True:
            kind, text = self.peek()
            if kind == 'op' and text in ops:
                self.take()
                r = self.level(n + 1)
                v = self.apply(text, v, r)
            else:
                return v

    @staticmethod
    def apply(op, a, b):
        if op == '+':
            return a + b
        if op == '-':
            return a - b
        if op == '*':
            return a * b
        if op == '/':
            if b == 0:
                raise AsmError("0 除算")
            return a // b
        if op == '%':
            if b == 0:
                raise AsmError("0 除算")
            return a % b
        if op == '&':
            return a & b
        if op == '|':
            return a | b
        if op == '^':
            return a ^ b
        if op == '<<':
            return a << b
        if op == '>>':
            return a >> b
        if op == '==':
            return 1 if a == b else 0
        if op == '!=':
            return 1 if a != b else 0
        if op == '<':
            return 1 if a < b else 0
        if op == '>':
            return 1 if a > b else 0
        if op == '<=':
            return 1 if a <= b else 0
        if op == '>=':
            return 1 if a >= b else 0
        if op == '&&':
            return 1 if (a and b) else 0
        if op == '||':
            return 1 if (a or b) else 0
        raise AsmError("未知の演算子 " + op)

    def unary(self):
        kind, text = self.peek()
        if kind == 'op' and text == '-':
            self.take()
            return -self.unary()
        if kind == 'op' and text == '+':
            self.take()
            return self.unary()
        if kind == 'op' and text == '~':
            self.take()
            return ~self.unary()
        if kind == 'op' and text == '!':
            self.take()
            return 0 if self.unary() else 1
        return self.primary()

    def primary(self):
        kind, text = self.take()
        if kind == 'op' and text == '(':
            v = self.level(0)
            k2, t2 = self.take()
            if not (k2 == 'op' and t2 == ')'):
                raise AsmError("')' がありません")
            return v
        if kind == 'num':
            return int(text, 10)
        if kind == 'hex1':
            return int(text[2:], 16)
        if kind == 'hex2':
            return int(text[:-1], 16)
        if kind == 'bin1':
            return int(text[2:], 2)
        if kind == 'bin2':
            return int(text[1:], 2)
        if kind == 'chr':
            return unescape_char(text)
        if kind == 'pc':
            return self.pc
        if kind == 'id':
            return self.resolve(text)
        raise AsmError("式の要素が解釈できません: %r" % (text,))


# --------------------------------------------------------------------------
# オペランドの分類
# --------------------------------------------------------------------------

def _is_quote_start(prev, c):
    """' が文字リテラルの始まりかどうか。AF' のアポストロフィは違う。"""
    if c == '"':
        return True
    return not (prev and (prev.isalnum() or prev == '_'))


def split_args(s):
    """カンマで分割する (括弧と文字列の中は無視)。"""
    out, depth, cur, i = [], 0, '', 0
    while i < len(s):
        c = s[i]
        if (c == '"' or c == "'") and _is_quote_start(cur[-1:] if cur else '', c):
            q = c
            cur += c
            i += 1
            while i < len(s):
                cur += s[i]
                if s[i] == '\\':
                    i += 1
                    if i < len(s):
                        cur += s[i]
                        i += 1
                    continue
                if s[i] == q:
                    i += 1
                    break
                i += 1
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        if c == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
            i += 1
            continue
        cur += c
        i += 1
    if cur.strip() or out:
        out.append(cur.strip())
    return [a for a in out if a != '']


class Operand:
    """
    kind:
      'r8'   val=レジスタ番号      A B C D E H L
      'mhl'                        (HL)
      'idx'  val=0xDD/0xFD, disp=式文字列    (IX+d) / (IY+d)
      'rp'   name='BC'...'SP','IX','IY','AF'
      'mem'  expr=式文字列         (nn)
      'mrp'  name='BC'/'DE'/'SP'/'HL'  (BC) (DE) ...
      'mc'                         (C)
      'cc'   val=条件番号
      'imm'  expr=式文字列
      'af2'                        AF'
      'i'/'r'                      I / R レジスタ
    """

    def __init__(self, kind, **kw):
        self.kind = kind
        self.val = kw.get('val')
        self.name = kw.get('name')
        self.expr = kw.get('expr')
        self.disp = kw.get('disp')

    def __repr__(self):
        return '<%s %r %r %r>' % (self.kind, self.val, self.name, self.expr)


IDX_RE = re.compile(r'^\(\s*(IX|IY)\s*(.*)\)$', re.IGNORECASE)


def classify(a):
    u = a.upper().strip()
    if u in R8:
        return Operand('r8', val=R8[u], name=u)
    if u == '(HL)':
        return Operand('mhl')
    if u == "AF'":
        return Operand('af2')
    if u in ('IX', 'IY'):
        return Operand('rp', name=u)
    if u in RP or u == 'AF':
        return Operand('rp', name=u)
    if u in ('I', 'R'):
        return Operand(u.lower())
    if u == '(C)':
        return Operand('mc')
    m = IDX_RE.match(a.strip())
    if m:
        reg = m.group(1).upper()
        rest = m.group(2).strip()
        if rest == '':
            rest = '0'
        elif rest[0] not in '+-':
            raise AsmError("(IX/IY±d) の書き方が不正です: " + a)
        return Operand('idx', val=0xDD if reg == 'IX' else 0xFD, disp=rest)
    if u.startswith('(') and u.endswith(')'):
        inner = a.strip()[1:-1].strip()
        iu = inner.upper()
        if iu in ('BC', 'DE', 'HL', 'SP'):
            return Operand('mrp', name=iu)
        return Operand('mem', expr=inner)
    if u in CC:
        # C は r8 と条件の両方。先に r8 を返しているので、ここに来るのは NZ/Z/NC/PO/PE/P/M
        return Operand('cc', val=CC[u], name=u)
    return Operand('imm', expr=a)


# --------------------------------------------------------------------------
# アセンブラ本体
# --------------------------------------------------------------------------

class Assembler:
    def __init__(self, include_dirs=None):
        self.symbols = {}
        self.image = bytearray(0x10000)
        self.written = bytearray(0x10000)   # どのアドレスに出力したか
        self.pc = 0
        self.include_dirs = include_dirs or []
        self.pass_no = 0
        self.last_global = ''
        self.errors = []
        self.listing = []
        self.promote = set()    # 届かない JR/DJNZ を JP に置き換える箇所
        self.promote_new = False
        self.cur_key = None

    # ---------------------------------------------------------------- utils

    _MNEMONICS = None

    @classmethod
    def known_mnemonics(cls):
        if cls._MNEMONICS is None:
            names = set(SIMPLE)
            names |= {'ORG', 'EQU', 'DB', 'DEFB', 'BYTE', 'DW', 'DEFW', 'WORD',
                      'DS', 'DEFS', 'ALIGN', 'ASSERT', 'END', 'INCLUDE'}
            names |= {n[2:].upper() for n in dir(cls) if n.startswith('i_')}
            cls._MNEMONICS = names
        return cls._MNEMONICS

    def expand_label(self, name):
        if name.startswith('.'):
            return self.last_global + name
        return name

    def resolve(self, name):
        key = self.expand_label(name)
        if key in self.symbols:
            return self.symbols[key]
        if name in self.symbols:
            return self.symbols[name]
        if self.pass_no == 1:
            return 0        # 1 パス目は未定義でも 0 とみなす
        raise AsmError("未定義のラベル: " + name)

    def ev(self, expr, pc=None):
        if pc is None:
            pc = self.pc
        toks = tokenize_expr(expr)
        if not toks:
            raise AsmError("式が空です")
        return ExprParser(toks, self.resolve, pc).parse()

    def emit(self, *bytes_):
        for b in bytes_:
            if self.pass_no == 2:
                if self.pc > 0xFFFF:
                    raise AsmError("出力アドレスが 64K を超えました")
                self.image[self.pc] = b & 0xFF
                self.written[self.pc] = 1
            self.pc += 1

    def db8(self, v, what='8bit'):
        if self.pass_no == 2 and not (-128 <= v <= 255):
            raise AsmError("%s の値が範囲外: %d" % (what, v))
        return v & 0xFF

    def rel(self, target):
        d = target - (self.pc + 1)
        if self.pass_no == 2 and not (-128 <= d <= 127):
            # 次の回で JP に置き換える
            if self.cur_key is not None and self.cur_key not in self.promote:
                self.promote.add(self.cur_key)
                self.promote_new = True
            return 0
        return d & 0xFF

    # ---------------------------------------------------------------- 読み込み

    def read_source(self, path):
        for d in [os.path.dirname(path) or '.'] + self.include_dirs:
            p = os.path.join(d, os.path.basename(path)) if d else path
            if os.path.isfile(path):
                p = path
            if os.path.isfile(p):
                with open(p, 'r', encoding='utf-8') as f:
                    return f.read(), p
        raise AsmError("ファイルが見つかりません: " + path)

    def flatten(self, path, seen=None):
        """INCLUDE を展開して (file, lineno, text) のリストにする。"""
        seen = seen or []
        text, real = self.read_source(path)
        out = []
        for n, line in enumerate(text.splitlines(), 1):
            s = strip_comment(line).strip()
            m = re.match(r'^(?:[A-Za-z_.][A-Za-z_.0-9]*:?\s+)?INCLUDE\s+"([^"]+)"\s*$', s, re.IGNORECASE)
            if m:
                inc = m.group(1)
                base = os.path.dirname(real)
                out.extend(self.flatten(os.path.join(base, inc), seen + [real]))
            else:
                out.append((real, n, line))
        return out

    # ---------------------------------------------------------------- 実行

    def assemble_file(self, path):
        """届かない JR/DJNZ を JP に置き換えながら、落ち着くまで通す。"""
        lines = self.flatten(path)
        for attempt in range(8):
            self.promote_new = False
            self.errors = []
            self.symbols = {}
            self.image = bytearray(0x10000)
            self.written = bytearray(0x10000)
            for p in (1, 2):
                self.pass_no = p
                self.pc = 0
                self.last_global = ''
                self.run(lines)
            if not self.promote_new:
                break
        else:
            raise AsmError("相対ジャンプの置き換えが収束しませんでした")
        if self.errors:
            raise AsmError("\n".join(self.errors))
        return self.image, self.written, self.symbols

    def run(self, lines):
        for (fname, lineno, raw) in lines:
            self.cur_key = (fname, lineno)
            try:
                self.do_line(raw)
            except AsmError as e:
                msg = "%s:%d: %s\n    %s" % (os.path.basename(fname), lineno, e, raw.strip())
                if self.pass_no == 2:
                    self.errors.append(msg)
                elif 'ファイルが見つかりません' in str(e):
                    self.errors.append(msg)
            except Exception as e:  # 想定外は常に報告する
                self.errors.append("%s:%d: 内部エラー %r\n    %s"
                                   % (os.path.basename(fname), lineno, e, raw.strip()))

    def do_line(self, raw):
        line = strip_comment(raw)
        if not line.strip():
            return

        # ラベル
        # ・行頭 (インデントなし) の識別子はラベル (ただしニーモニック名は除く)
        # ・インデントされていても ':' が付いていればラベル
        label = None
        indented = line[:1] in (' ', '\t')
        stripped = line.lstrip()
        m = re.match(r'^([A-Za-z_.][A-Za-z_.0-9]*)(:)?', stripped)
        if m:
            is_label = bool(m.group(2))
            if not is_label and not indented:
                is_label = m.group(1).upper() not in self.known_mnemonics()
            if not is_label:
                # "name EQU expr" はインデントされていてもラベル定義
                nxt = stripped[m.end():].lstrip().split(None, 1)
                if nxt and nxt[0].upper() == 'EQU':
                    is_label = True
            if is_label:
                label = m.group(1)
                stripped = stripped[m.end():]
        line = stripped.strip()

        parts = line.split(None, 1)
        mnem = parts[0].upper() if parts else ''
        rest = parts[1].strip() if len(parts) > 1 else ''

        # EQU はラベルを定数にする
        if mnem == 'EQU':
            if label is None:
                raise AsmError("EQU にラベルがありません")
            name = self.expand_label(label)
            if not label.startswith('.'):
                self.last_global = label
            v = self.ev(rest)
            if self.pass_no == 2 and self.symbols.get(name) != v:
                pass    # 2 パス目で確定した値を採用する
            self.symbols[name] = v
            return

        if label is not None:
            name = self.expand_label(label)
            if not label.startswith('.'):
                self.last_global = label
            if self.pass_no == 1 and name in self.symbols:
                raise AsmError("ラベルの二重定義: " + name)
            self.symbols[name] = self.pc

        if not mnem:
            return

        args = split_args(rest)
        self.encode(mnem, args, rest)

    # ---------------------------------------------------------------- 疑似命令

    def pseudo(self, mnem, args, rest):
        if mnem == 'ORG':
            self.pc = self.ev(args[0]) & 0xFFFF
            return True
        if mnem in ('DB', 'DEFB', 'BYTE'):
            for a in args:
                if a.startswith('"') and a.endswith('"') and len(a) >= 2:
                    for ch in decode_string(a):
                        self.emit(ch)
                else:
                    self.emit(self.db8(self.ev(a), 'DB'))
            return True
        if mnem in ('DW', 'DEFW', 'WORD'):
            for a in args:
                v = self.ev(a) & 0xFFFF
                self.emit(v & 0xFF, v >> 8)
            return True
        if mnem in ('DS', 'DEFS'):
            n = self.ev(args[0])
            fill = self.ev(args[1]) if len(args) > 1 else 0
            if n < 0:
                raise AsmError("DS の長さが負です")
            for _ in range(n):
                self.emit(fill & 0xFF)
            return True
        if mnem == 'ALIGN':
            n = self.ev(args[0])
            while self.pc % n:
                self.emit(0)
            return True
        if mnem == 'ASSERT':
            if self.pass_no == 2 and not self.ev(args[0]):
                msg = decode_string(args[1]) if len(args) > 1 else b''
                raise AsmError("ASSERT 失敗: %s (%s)"
                               % (args[0], msg.decode('utf-8', 'replace')))
            return True
        if mnem == 'END':
            return True
        return False

    # ---------------------------------------------------------------- 命令

    def encode(self, mnem, args, rest):
        if self.pseudo(mnem, args, rest):
            return

        if mnem in SIMPLE and not args:
            self.emit(*SIMPLE[mnem])
            return

        ops = [classify(a) for a in args]
        fn = getattr(self, 'i_' + mnem.lower(), None)
        if fn is None:
            raise AsmError("未知の命令: " + mnem)
        fn(ops)

    # --- 補助: (HL)/(IX+d)/r8 をまとめて扱う ------------------------------

    def rm_prefix(self, o):
        """r8 / (HL) / (IX+d) → (prefix_list, reg_code, disp_list)"""
        if o.kind == 'r8':
            return [], o.val, []
        if o.kind == 'mhl':
            return [], 6, []
        if o.kind == 'idx':
            return [o.val], 6, [self.db8(self.ev(o.disp), '(IX/IY±d)')]
        raise AsmError("レジスタか (HL)/(IX+d) が必要です: %r" % (o,))

    def rp_code(self, o, table=None):
        table = table or RP
        name = o.name
        if name in ('IX', 'IY'):
            return (0xDD if name == 'IX' else 0xFD), table['HL']
        if name not in table:
            raise AsmError("16bit レジスタが不正です: %r" % (name,))
        return None, table[name]

    # --- 8bit ロード ------------------------------------------------------

    def i_ld(self, ops):
        if len(ops) != 2:
            raise AsmError("LD の引数は 2 つです")
        d, s = ops

        # LD A,(nn) / LD (nn),A
        if d.kind == 'r8' and d.val == 7 and s.kind == 'mem':
            v = self.ev(s.expr) & 0xFFFF
            self.emit(0x3A, v & 0xFF, v >> 8)
            return
        if d.kind == 'mem' and s.kind == 'r8' and s.val == 7:
            v = self.ev(d.expr) & 0xFFFF
            self.emit(0x32, v & 0xFF, v >> 8)
            return
        # LD A,(BC)/(DE) と逆
        if d.kind == 'r8' and d.val == 7 and s.kind == 'mrp' and s.name in ('BC', 'DE'):
            self.emit(0x0A if s.name == 'BC' else 0x1A)
            return
        if d.kind == 'mrp' and d.name in ('BC', 'DE') and s.kind == 'r8' and s.val == 7:
            self.emit(0x02 if d.name == 'BC' else 0x12)
            return
        # LD A,I / LD A,R / LD I,A / LD R,A
        if d.kind == 'r8' and d.val == 7 and s.kind in ('i', 'r'):
            self.emit(0xED, 0x57 if s.kind == 'i' else 0x5F)
            return
        if d.kind in ('i', 'r') and s.kind == 'r8' and s.val == 7:
            self.emit(0xED, 0x47 if d.kind == 'i' else 0x4F)
            return
        # LD SP,HL / IX / IY
        if d.kind == 'rp' and d.name == 'SP' and s.kind == 'rp' and s.name in ('HL', 'IX', 'IY'):
            if s.name != 'HL':
                self.emit(0xDD if s.name == 'IX' else 0xFD)
            self.emit(0xF9)
            return
        # 16bit 即値 / (nn)
        if d.kind == 'rp':
            pre, code = self.rp_code(d)
            if s.kind == 'imm':
                v = self.ev(s.expr) & 0xFFFF
                if pre:
                    self.emit(pre)
                self.emit(0x01 | (code << 4), v & 0xFF, v >> 8)
                return
            if s.kind == 'mem':
                v = self.ev(s.expr) & 0xFFFF
                if pre:
                    self.emit(pre, 0x2A, v & 0xFF, v >> 8)
                elif d.name == 'HL':
                    self.emit(0x2A, v & 0xFF, v >> 8)
                else:
                    self.emit(0xED, 0x4B | (code << 4), v & 0xFF, v >> 8)
                return
            raise AsmError("LD の組み合わせが不正です")
        if d.kind == 'mem' and s.kind == 'rp':
            pre, code = self.rp_code(s)
            v = self.ev(d.expr) & 0xFFFF
            if pre:
                self.emit(pre, 0x22, v & 0xFF, v >> 8)
            elif s.name == 'HL':
                self.emit(0x22, v & 0xFF, v >> 8)
            else:
                self.emit(0xED, 0x43 | (code << 4), v & 0xFF, v >> 8)
            return

        # 8bit: r/(HL)/(IX+d) ← 即値
        if d.kind in ('r8', 'mhl', 'idx') and s.kind == 'imm':
            pre, dc, disp = self.rm_prefix(d)
            v = self.db8(self.ev(s.expr), 'LD の即値')
            self.emit(*pre)
            self.emit(0x06 | (dc << 3), *disp)
            self.emit(v)
            return
        # 8bit: r ← r
        if d.kind in ('r8', 'mhl', 'idx') and s.kind in ('r8', 'mhl', 'idx'):
            if d.kind == 'idx' and s.kind == 'idx':
                raise AsmError("(IX+d) 同士の LD はできません")
            if (d.kind == 'mhl' and s.kind == 'mhl'):
                raise AsmError("LD (HL),(HL) はありません")
            pre1, dc, disp1 = self.rm_prefix(d)
            pre2, sc, disp2 = self.rm_prefix(s)
            self.emit(*(pre1 or pre2))
            self.emit(0x40 | (dc << 3) | sc, *(disp1 or disp2))
            return
        raise AsmError("LD の組み合わせが不正です: %r" % (ops,))

    # --- 算術論理 --------------------------------------------------------

    def alu_generic(self, name, ops):
        code = ALU[name]
        # ADD/ADC/SBC の 16bit 形
        if name in ('ADD', 'ADC', 'SBC') and len(ops) == 2 and ops[0].kind == 'rp':
            dst, src = ops
            if dst.name in ('HL', 'IX', 'IY'):
                pre = None
                if dst.name != 'HL':
                    pre = 0xDD if dst.name == 'IX' else 0xFD
                sname = src.name if src.kind == 'rp' else None
                if sname is None:
                    raise AsmError("%s の第2引数が不正です" % name)
                if pre and sname in ('IX', 'IY'):
                    if sname != dst.name:
                        raise AsmError("ADD IX,IY はできません")
                    sname = 'HL'
                elif sname in ('IX', 'IY'):
                    raise AsmError("ADD HL,IX はできません")
                if sname not in RP:
                    raise AsmError("%s の第2引数が不正です" % name)
                rc = RP[sname]
                if name == 'ADD':
                    if pre:
                        self.emit(pre)
                    self.emit(0x09 | (rc << 4))
                else:
                    if pre:
                        raise AsmError("ADC/SBC は IX/IY に使えません")
                    self.emit(0xED, (0x4A if name == 'ADC' else 0x42) | (rc << 4))
                return
            raise AsmError("%s の第1引数が不正です" % name)

        # A, x の形 (A は省略可)
        if len(ops) == 2:
            if not (ops[0].kind == 'r8' and ops[0].val == 7):
                raise AsmError("%s の第1引数は A です" % name)
            src = ops[1]
        elif len(ops) == 1:
            src = ops[0]
        else:
            raise AsmError("%s の引数が不正です" % name)

        if src.kind == 'imm':
            self.emit(0xC6 | (code << 3), self.db8(self.ev(src.expr), name))
            return
        pre, sc, disp = self.rm_prefix(src)
        self.emit(*pre)
        self.emit(0x80 | (code << 3) | sc, *disp)

    def i_add(self, ops):
        self.alu_generic('ADD', ops)

    def i_adc(self, ops):
        self.alu_generic('ADC', ops)

    def i_sub(self, ops):
        self.alu_generic('SUB', ops)

    def i_sbc(self, ops):
        self.alu_generic('SBC', ops)

    def i_and(self, ops):
        self.alu_generic('AND', ops)

    def i_xor(self, ops):
        self.alu_generic('XOR', ops)

    def i_or(self, ops):
        self.alu_generic('OR', ops)

    def i_cp(self, ops):
        self.alu_generic('CP', ops)

    def i_inc(self, ops):
        self.incdec(ops, True)

    def i_dec(self, ops):
        self.incdec(ops, False)

    def incdec(self, ops, is_inc):
        o = ops[0]
        if o.kind == 'rp':
            pre, code = self.rp_code(o)
            if pre:
                self.emit(pre)
            self.emit((0x03 if is_inc else 0x0B) | (code << 4))
            return
        pre, c, disp = self.rm_prefix(o)
        self.emit(*pre)
        self.emit((0x04 if is_inc else 0x05) | (c << 3), *disp)

    # --- 分岐 ------------------------------------------------------------

    def i_jp(self, ops):
        if len(ops) == 1:
            o = ops[0]
            if o.kind == 'mhl':
                self.emit(0xE9)
                return
            if o.kind == 'mrp' and o.name == 'HL':
                self.emit(0xE9)
                return
            if o.kind == 'mem':
                # JP (IX) は (IX+0) 扱いにならないので別処理
                iu = o.expr.upper().strip()
                if iu in ('IX', 'IY'):
                    self.emit(0xDD if iu == 'IX' else 0xFD, 0xE9)
                    return
            if o.kind == 'idx' and o.disp.strip() in ('0', '+0'):
                self.emit(o.val, 0xE9)
                return
            v = self.ev(o.expr) & 0xFFFF
            self.emit(0xC3, v & 0xFF, v >> 8)
            return
        if len(ops) == 2 and ops[0].kind in ('cc', 'r8'):
            cc = self.cond_of(ops[0])
            v = self.ev(ops[1].expr) & 0xFFFF
            self.emit(0xC2 | (cc << 3), v & 0xFF, v >> 8)
            return
        raise AsmError("JP の引数が不正です")

    @staticmethod
    def cond_of(o):
        if o.kind == 'cc':
            return o.val
        if o.kind == 'r8' and o.name == 'C':
            return CC['C']
        raise AsmError("条件が不正です: %r" % (o,))

    def i_jr(self, ops):
        promoted = self.cur_key in self.promote
        if len(ops) == 1:
            t = self.ev(ops[0].expr)
            if promoted:
                v = t & 0xFFFF
                self.emit(0xC3, v & 0xFF, v >> 8)
                return
            self.emit(0x18)
            self.emit(self.rel(t))
            return
        cc = self.cond_of(ops[0])
        if cc > 3:
            raise AsmError("JR で使える条件は NZ/Z/NC/C だけです")
        t = self.ev(ops[1].expr)
        if promoted:
            v = t & 0xFFFF
            self.emit(0xC2 | (cc << 3), v & 0xFF, v >> 8)
            return
        self.emit(0x20 | (cc << 3))
        self.emit(self.rel(t))

    def i_djnz(self, ops):
        t = self.ev(ops[0].expr)
        if self.cur_key in self.promote:
            # DEC B + JP NZ に置き換える (フラグが変わる点だけ注意)
            v = t & 0xFFFF
            self.emit(0x05)
            self.emit(0xC2, v & 0xFF, v >> 8)
            return
        self.emit(0x10)
        self.emit(self.rel(t))

    def i_call(self, ops):
        if len(ops) == 1:
            v = self.ev(ops[0].expr) & 0xFFFF
            self.emit(0xCD, v & 0xFF, v >> 8)
            return
        cc = self.cond_of(ops[0])
        v = self.ev(ops[1].expr) & 0xFFFF
        self.emit(0xC4 | (cc << 3), v & 0xFF, v >> 8)

    def i_ret(self, ops):
        if not ops:
            self.emit(0xC9)
            return
        cc = self.cond_of(ops[0])
        self.emit(0xC0 | (cc << 3))

    def i_rst(self, ops):
        v = self.ev(ops[0].expr)
        if v % 8 or not (0 <= v <= 0x38):
            raise AsmError("RST は 0,8,10h..38h です")
        self.emit(0xC7 | v)

    # --- スタック --------------------------------------------------------

    def i_push(self, ops):
        pre, code = self.rp_code(ops[0], RP_PUSH)
        if pre:
            self.emit(pre)
        self.emit(0xC5 | (code << 4))

    def i_pop(self, ops):
        pre, code = self.rp_code(ops[0], RP_PUSH)
        if pre:
            self.emit(pre)
        self.emit(0xC1 | (code << 4))

    def i_ex(self, ops):
        a, b = ops
        if a.kind == 'rp' and a.name == 'DE' and b.kind == 'rp' and b.name == 'HL':
            self.emit(0xEB)
            return
        if a.kind == 'rp' and a.name == 'AF' and b.kind == 'af2':
            self.emit(0x08)
            return
        if a.kind == 'mrp' and a.name == 'SP' and b.kind == 'rp':
            if b.name == 'HL':
                self.emit(0xE3)
                return
            if b.name in ('IX', 'IY'):
                self.emit(0xDD if b.name == 'IX' else 0xFD, 0xE3)
                return
        raise AsmError("EX の組み合わせが不正です")

    # --- 入出力 ----------------------------------------------------------

    def i_in(self, ops):
        d, s = ops
        if d.kind == 'r8' and d.val == 7 and s.kind == 'mem':
            self.emit(0xDB, self.db8(self.ev(s.expr), 'IN のポート'))
            return
        if d.kind == 'r8' and s.kind == 'mc':
            self.emit(0xED, 0x40 | (d.val << 3))
            return
        raise AsmError("IN の組み合わせが不正です")

    def i_out(self, ops):
        d, s = ops
        if d.kind == 'mem' and s.kind == 'r8' and s.val == 7:
            self.emit(0xD3, self.db8(self.ev(d.expr), 'OUT のポート'))
            return
        if d.kind == 'mc' and s.kind == 'r8':
            self.emit(0xED, 0x41 | (s.val << 3))
            return
        if d.kind == 'mc' and s.kind == 'imm' and self.ev(s.expr) == 0:
            self.emit(0xED, 0x71)
            return
        raise AsmError("OUT の組み合わせが不正です")

    def i_im(self, ops):
        v = self.ev(ops[0].expr)
        self.emit(0xED, {0: 0x46, 1: 0x56, 2: 0x5E}[v])

    # --- シフト・ローテート・ビット -------------------------------------

    def rot_generic(self, name, ops):
        code = ROT[name]
        pre, c, disp = self.rm_prefix(ops[0])
        if pre:
            self.emit(pre[0], 0xCB, *disp)
            self.emit(0x00 | (code << 3) | c)
        else:
            self.emit(0xCB, 0x00 | (code << 3) | c)

    def i_rlc(self, ops):
        self.rot_generic('RLC', ops)

    def i_rrc(self, ops):
        self.rot_generic('RRC', ops)

    def i_rl(self, ops):
        self.rot_generic('RL', ops)

    def i_rr(self, ops):
        self.rot_generic('RR', ops)

    def i_sla(self, ops):
        self.rot_generic('SLA', ops)

    def i_sra(self, ops):
        self.rot_generic('SRA', ops)

    def i_sll(self, ops):
        self.rot_generic('SLL', ops)

    def i_srl(self, ops):
        self.rot_generic('SRL', ops)

    def bit_generic(self, base, ops):
        n = self.ev(ops[0].expr)
        if not (0 <= n <= 7):
            raise AsmError("ビット番号は 0..7 です")
        pre, c, disp = self.rm_prefix(ops[1])
        if pre:
            self.emit(pre[0], 0xCB, *disp)
            self.emit(base | (n << 3) | c)
        else:
            self.emit(0xCB, base | (n << 3) | c)

    def i_bit(self, ops):
        self.bit_generic(0x40, ops)

    def i_res(self, ops):
        self.bit_generic(0x80, ops)

    def i_set(self, ops):
        self.bit_generic(0xC0, ops)


def strip_comment(line):
    out, i, n = '', 0, len(line)
    while i < n:
        c = line[i]
        if c == ';':
            break
        if c in '"\'' and _is_quote_start(out[-1:] if out else '', c):
            q = c
            out += c
            i += 1
            while i < n:
                out += line[i]
                if line[i] == '\\':
                    i += 1
                    if i < n:
                        out += line[i]
                        i += 1
                    continue
                if line[i] == q:
                    i += 1
                    break
                i += 1
            continue
        out += c
        i += 1
    return out


def decode_string(a):
    if not (a.startswith('"') and a.endswith('"')):
        raise AsmError("文字列が必要です: " + a)
    body = a[1:-1]
    out = bytearray()
    i = 0
    while i < len(body):
        c = body[i]
        if c == '\\' and i + 1 < len(body):
            nxt = body[i + 1]
            out.append({'n': 10, 'r': 13, 't': 9, '0': 0,
                        '\\': 92, '"': 34, "'": 39}.get(nxt, ord(nxt)))
            i += 2
            continue
        out.append(ord(c))
        i += 1
    return bytes(out)


def assemble(path, include_dirs=None):
    a = Assembler(include_dirs)
    image, written, symbols = a.assemble_file(path)
    return image, written, symbols


def main(argv):
    if len(argv) < 2:
        print("使い方: z80asm.py source.asm [-o out.bin] [-s out.sym] [--region start:end]")
        return 1
    src = argv[1]
    out = None
    sym = None
    regions = []
    i = 2
    while i < len(argv):
        if argv[i] == '-o':
            out = argv[i + 1]
            i += 2
        elif argv[i] == '-s':
            sym = argv[i + 1]
            i += 2
        elif argv[i] == '--region':
            s, e = argv[i + 1].split(':')
            regions.append((int(s, 0), int(e, 0)))
            i += 2
        else:
            print("不明な引数:", argv[i])
            return 1
    try:
        image, written, symbols = assemble(src)
    except AsmError as e:
        print("アセンブルエラー:\n" + str(e))
        return 1
    used = [i for i in range(0x10000) if written[i]]
    print("出力範囲: %04Xh - %04Xh (%d バイト)" % (used[0], used[-1], len(used)))
    if out:
        if regions:
            data = bytearray()
            for (s, e) in regions:
                data += image[s:e]
            with open(out, 'wb') as f:
                f.write(data)
        else:
            with open(out, 'wb') as f:
                f.write(image[used[0]:used[-1] + 1])
    if sym:
        with open(sym, 'w', encoding='utf-8') as f:
            for k in sorted(symbols, key=lambda k: symbols[k]):
                f.write("%04X %s\n" % (symbols[k] & 0xFFFF, k))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
