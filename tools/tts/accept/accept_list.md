# Accept list

A clip passes a recognizer when its fCER (CER after folding vowel length and nasal marks) is <= 0.15, the rule of lab.py's summary.md. A phrase is accepted for a voice when at least one of its clips (any carrier cut, take or trim) passes at least one recognizer, heard alone or right after the context sentence. Recognizer round trip only: this says nothing about how natural a clip sounds.

## Inputs

- run-36722519301: 672 rows, recognizers mms, vakyansh; 127 keys only in this run (svara-label 48, svara-label-trim 23, svara-ref 48, svara-ref-trim 8)
- run-39361763954: 545 rows, recognizers mms, vakyansh, whisper-ct2; 0 keys only in this run
- merged: 672 clips. Where both runs scored a clip, the newer run's values are used.
- mms: 545 clips scored in both runs, 0 differ (0 fields), 0 pass/fail flips, 0 in-context flips
- vakyansh: 545 clips scored in both runs, 0 differ (0 fields), 0 pass/fail flips, 0 in-context flips

## Clips passing per set (plain fCER <= 0.15)

| set | n | mms | vakyansh | whisper-ct2 |
|---|---|---|---|---|
| context | 2 | 2/2 | 2/2 | 2/2 |
| controls | 14 | 0/14 | 0/14 | 0/14 |
| humans-sentences | 30 | 30/30 | 28/30 | 9/30 |
| humans-words | 8 | 2/8 | 4/8 | 3/8 |
| indic-c1 | 95 | 54/95 | 70/95 | 78/95 |
| indic-c2 | 95 | 55/95 | 73/95 | 82/95 |
| indic-c3 | 95 | 57/95 | 69/95 | 79/95 |
| indic-nosplit | 95 | 38/95 | 55/95 | 58/95 |
| indic-old | 95 | 34/95 | 47/95 | 51/95 |
| svara-label | 48 | 5/48 | 4/48 | - |
| svara-label-trim | 23 | 11/23 | 12/23 | - |
| svara-probe | 16 | 6/16 | 5/16 | 6/16 |
| svara-ref | 48 | 3/48 | 3/48 | - |
| svara-ref-trim | 8 | 4/8 | 6/8 | - |

## Human baseline

Real Gujarati speech through the same recognizers.

| set | n | mms | vakyansh | whisper-ct2 |
|---|---|---|---|---|
| humans-words | 8 | 2/8 (25%) | 4/8 (50%) | 3/8 (38%) |
| humans-sentences | 30 | 30/30 (100%) | 28/30 (93%) | 9/30 (30%) |

## Phrases

54 of 56 phrases have at least one accepted synthetic voice; 53 have one in the voice the app uses for that phrase.

Candidates are written family/voice with the recognizers that passed it; * marks a candidate that passed only in context.

| id | phrase | app voice | accepted | not accepted |
|---|---|---|---|---|
| a1 | કેમ છો? | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2); svara-label/female (mms, vakyansh); svara-label/male (mms, vakyansh); svara-probe/male (mms, vakyansh, whisper-ct2); svara-ref/male (vakyansh) | svara-probe/female; svara-ref/female |
| a2 | મજામાં | female | indic-carrier/female (mms, vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female |
| a3 | સારું | male | indic-carrier/male (vakyansh, whisper-ct2); indic-nosplit/male (vakyansh, whisper-ct2); indic-old/male (vakyansh, whisper-ct2) | - |
| a4 | હા | female | indic-carrier/female (whisper-ct2); indic-nosplit/female (whisper-ct2); indic-old/female (whisper-ct2); svara-label/female (vakyansh); svara-ref/female (mms, vakyansh) | svara-label/male; svara-ref/male |
| a5 | ના. | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (vakyansh, whisper-ct2); indic-old/female (vakyansh, whisper-ct2); svara-label/male (mms, vakyansh); svara-probe/male (mms)*; svara-ref/male (vakyansh) | svara-label/female; svara-probe/female; svara-ref/female |
| a6 | આભાર. | female | indic-carrier/female (mms, vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female; svara-label/female; svara-label/male; svara-ref/female; svara-ref/male |
| a7 | માફ કરજો! | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| a8 | આવજો. | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (vakyansh); indic-old/male (vakyansh) | - |
| b1 | તમારું નામ શું છે? | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2); svara-probe/male (mms, vakyansh, whisper-ct2) | svara-probe/female |
| b2 | મારું નામ મીરા છે | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (mms, vakyansh, whisper-ct2); indic-old/female (mms, vakyansh, whisper-ct2) | - |
| b3 | તમે ક્યાંથી છો? | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| b4 | હું અમેરિકાથી છું. | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (mms, vakyansh, whisper-ct2); indic-old/female (mms, vakyansh, whisper-ct2) | - |
| b5 | મળીને આનંદ થયો. | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (mms, vakyansh, whisper-ct2); indic-old/female (mms, vakyansh, whisper-ct2) | - |
| b6 | હું | male | indic-nosplit/male (whisper-ct2) | indic-carrier/male; indic-old/male |
| b7 | તમે | female | indic-carrier/female (vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female |
| c1 | મને સમજાયું નહીં. | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| c2 | ધીમે બોલો? | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (vakyansh, whisper-ct2); indic-old/female (vakyansh, whisper-ct2) | - |
| c3 | ફરીથી કહો | male | indic-carrier/male (vakyansh, whisper-ct2); indic-old/male (mms, whisper-ct2) | indic-nosplit/male |
| c4 | મને ગુજરાતી થોડું આવડે છે. | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (mms, vakyansh, whisper-ct2); indic-old/female (mms, vakyansh, whisper-ct2); svara-ref/male (mms, vakyansh) | svara-label/female; svara-label/male; svara-probe/female; svara-probe/male; svara-ref/female |
| c5 | આ શું છે? | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (vakyansh, whisper-ct2); indic-old/male (vakyansh)* | - |
| c6 | ક્યાં છે? | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| c7 | ખબર નથી. | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (mms, vakyansh, whisper-ct2); indic-old/female (mms, vakyansh, whisper-ct2); svara-label/male (mms, vakyansh) | svara-label/female; svara-ref/female; svara-ref/male |
| d1 | એક | female | indic-carrier/female (whisper-ct2) | indic-nosplit/female; indic-old/female |
| d2 | બે. | female | indic-carrier/female (vakyansh, whisper-ct2); indic-nosplit/female (vakyansh, whisper-ct2); indic-old/female (vakyansh, whisper-ct2) | - |
| d3 | ત્રણ | female | indic-carrier/female (whisper-ct2) | indic-nosplit/female; indic-old/female |
| d4 | ચાર. | female | indic-carrier/female (vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female |
| d5 | પાંચ | female | indic-carrier/female (vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female |
| d6 | છ. | female | none | indic-carrier/female; indic-nosplit/female; indic-old/female |
| d7 | સાત. | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (vakyansh) | indic-old/female |
| d8 | આઠ. | female | indic-carrier/female (vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female; svara-label/female; svara-label/male; svara-ref/female; svara-ref/male |
| d9 | નવ. | female | indic-carrier/female (vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female |
| d10 | દસ | female | indic-carrier/female (vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female |
| e1 | પાણી | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (vakyansh, whisper-ct2); indic-old/male (vakyansh, whisper-ct2) | - |
| e2 | ચા | female | svara-label/male (vakyansh)* | indic-carrier/female; indic-nosplit/female; indic-old/female; svara-label/female; svara-ref/female; svara-ref/male |
| e3 | ખાવાનું | female | indic-carrier/female (vakyansh, whisper-ct2) | indic-nosplit/female; indic-old/female |
| e4 | મને ભૂખ લાગી છે. | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| e5 | મને તરસ લાગી છે | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| e6 | બહુ સરસ! | male | indic-carrier/male (vakyansh, whisper-ct2) | indic-nosplit/male; indic-old/male |
| e7 | બસ, થયું | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (vakyansh) | indic-old/female |
| e8 | મને પાણી જોઈએ છે. | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| f1 | મમ્મી | male | indic-carrier/male (vakyansh, whisper-ct2) | indic-nosplit/male; indic-old/male |
| f2 | પપ્પા | male | indic-carrier/male (whisper-ct2) | indic-nosplit/male; indic-old/male |
| f3 | ભાઈ | female | none | indic-carrier/female; indic-nosplit/female; indic-old/female |
| f4 | બહેન | female | indic-carrier/female (whisper-ct2) | indic-nosplit/female; indic-old/female |
| f5 | દીકરો | male | indic-carrier/male (vakyansh, whisper-ct2) | indic-nosplit/male; indic-old/male |
| f6 | દીકરી | male | indic-carrier/male (vakyansh, whisper-ct2); indic-old/male (vakyansh)* | indic-nosplit/male |
| f7 | મિત્ર | male | indic-carrier/male (vakyansh, whisper-ct2); indic-nosplit/male (whisper-ct2); indic-old/male (vakyansh, whisper-ct2) | - |
| f8 | ઘર | male | indic-carrier/male (whisper-ct2); svara-label/female (mms) | indic-nosplit/male; indic-old/male; svara-label/male; svara-ref/female; svara-ref/male |
| g1 | ચાલો! | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (whisper-ct2); indic-old/male (vakyansh, whisper-ct2) | - |
| g2 | બેસો. | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (vakyansh, whisper-ct2); indic-old/male (vakyansh, whisper-ct2) | - |
| g3 | આવો | male | indic-carrier/male (whisper-ct2) | indic-nosplit/male; indic-old/male |
| g4 | કેટલા વાગ્યા? | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| g5 | કેટલા પૈસા? | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| g6 | મને ગમે છે. | male | indic-carrier/male (mms, vakyansh, whisper-ct2); indic-nosplit/male (mms, vakyansh, whisper-ct2); indic-old/male (mms, vakyansh, whisper-ct2) | - |
| g7 | આજે | male | indic-nosplit/male (vakyansh)*; indic-old/male (vakyansh, whisper-ct2) | indic-carrier/male |
| g8 | કાલે. | female | indic-carrier/female (mms, vakyansh, whisper-ct2); indic-nosplit/female (whisper-ct2); indic-old/female (mms, vakyansh, whisper-ct2) | - |

## Missing data

- svara-label: no whisper-ct2 scores in either run
- svara-label-trim: no whisper-ct2 scores in either run
- svara-ref: no whisper-ct2 scores in either run
- svara-ref-trim: no whisper-ct2 scores in either run
- Human recordings have no in-context scores (only the male/female TTS voices have a context sentence).
- Pass counts here use the plain fCER, like summary.md; the in-context scores only widen the phrase accept decision.
