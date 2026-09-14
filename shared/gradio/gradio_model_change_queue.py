"""Serialize browser model-selection requests through their form refresh."""
from functools import wraps

from gradio import blocks
from gradio.events import EventListenerMethod


# These hooks target the pinned Gradio 5.29 frontend. Queue captured requests,
# not DOM clicks: select event data and the user's requested filter stay intact.
_QUEUE_JS = """
const wangpModelQueues = new Map();
function wangpModelEnqueue(group, run) {
    let queue = wangpModelQueues.get(group);
    if (!queue) wangpModelQueues.set(group, queue = []);
    queue.push(run);
    if (queue.length === 1) run();
}
function wangpModelRelease(group) {
    const queue = wangpModelQueues.get(group);
    if (!queue) return;
    queue.shift();
    if (queue.length) queue[0]();
    else wangpModelQueues.delete(group);
}
"""
_REPLACEMENTS = {
    'function Jt(S,J=null,K=null){': _QUEUE_JS + 'function Jt(S,J=null,K=null){',
    'if(pe===void 0)return;const R=pe;': 'if(pe===void 0)return;if(pe.wangp_model_end){wangpModelRelease(S);return}const R=pe;',
    'async function Qt(W,Ie=!1){': 'async function Qt(W,Ie=!1,wangpAdmitted=false){if(R.wangp_model_root&&!wangpAdmitted){wangpModelEnqueue(R.wangp_model_root[0],()=>Qt(W,Ie,true));return}',
    'pl(Ee,ne),Mn(n)}function Bo': 'pl(Ee,ne),Mn(n);if(R.wangp_model_root){const [ack,index]=R.wangp_model_root,value=Ee[index];if(value?.__type__==="update"&&!("value"in value))Jt(ack)}}function Bo',
    'else if(ne.stage==="error"){': 'else if(ne.stage==="error"){if(R.wangp_model_root)Jt(R.wangp_model_root[0]);',
    'catch(ae){if(d.closed)return;': 'catch(ae){if(R.wangp_model_root)Jt(R.wangp_model_root[0]);if(d.closed)return;',
}


def _walk_tail(app, head):
    """Follow trigger_after links from head to the end of its chain.

    Returns (tail, length). Upstream assumed each node had exactly one child and
    destructured with `[child] = children`; a plugin can legitimately chain its
    own handler off the same node, so prefer the first real child instead. A
    `fn is None` child is a JS-only continuation and still terminates the walk,
    exactly as before.
    """
    tail, length = head, 0
    while True:
        children = [fn for fn in app.fns.values() if fn.trigger_after == tail._id]
        real = [fn for fn in children if fn.fn is not None]
        if not real:
            break
        tail = real[0]
        length += 1
    return tail, length


def _prepare(app):
    if not hasattr(app, '_wangp_model_switch_acks'):
        app._wangp_model_switch_acks = {}
    for target in app.blocks.values():
        if target.elem_id != 'wangp_model_choice_target' or target._id in app._wangp_model_switch_acks:
            continue
        parents = {fn.trigger_after for fn in app.fns.values()}
        candidates = [fn for fn in app.fns.values() if (target._id, 'change') in fn.targets and fn._id in parents]
        if not candidates:
            continue
        # Upstream did `[tail] = candidates`, which raises ValueError the moment a
        # plugin registers its own .change() on this component -- e.g.
        # MiniMaxH3Mod-for-WanGP's inline RefMods panel visibility toggle. That
        # killed startup outright. Pick the longest chain instead: Wan2GP's own
        # model-switch handler refreshes the entire form, so it always chains
        # further than a plugin's single-step listener.
        tail = max((_walk_tail(app, fn) for fn in candidates), key=lambda pair: pair[1])[0]
        # Gradio dispatches this frontend-only continuation after its pending
        # output updates settle. It adds no HTTP request or wait to a single swap.
        _, ack = app.default_config.set_event_trigger([EventListenerMethod(None, 'then')], None, None, None, js='()=>{}', trigger_after=tail._id, queue=False, api_name=False)
        app._wangp_model_switch_acks[target._id] = ack


def install():
    original = blocks.Blocks.get_config_file
    if getattr(original, '_wangp_model_queue', False):
        return

    @wraps(original)
    def get_config_file(self):
        _prepare(self)
        config = original(self)
        for dependency in config['dependencies']:
            for target, ack in self._wangp_model_switch_acks.items():
                if dependency['id'] == ack:
                    dependency['wangp_model_end'] = True
                elif dependency['trigger_after'] is None and target in dependency['outputs']:
                    dependency['wangp_model_root'] = [ack, dependency['outputs'].index(target)]
        return config

    get_config_file._wangp_model_queue = True
    blocks.Blocks.get_config_file = get_config_file
