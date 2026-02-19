import 'package:flutter/material.dart';
import 'package:now_chat/app/router.dart';
import 'package:now_chat/providers/agent_provider.dart';
import 'package:provider/provider.dart';

/// 工具主页：两列卡片列表。
class AgentPage extends StatelessWidget {
  const AgentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final agents = context.watch<AgentProvider>().agents;

    return Scaffold(
      appBar: AppBar(
        title: const Text('工具'),
        actions: [
          IconButton(
            tooltip: '新建工具',
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.agentForm,
              );
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: agents.isEmpty
          ? Center(
              child: Text(
                '还没有工具，点击右上角创建',
                style: TextStyle(
                  fontSize: 14,
                  color: color.onSurfaceVariant,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 104,
              ),
              itemCount: agents.length,
              itemBuilder: (context, index) {
                final agent = agents[index];
                final summary = agent.summary.trim().isEmpty
                    ? agent.prompt.trim()
                    : agent.summary.trim();
                return Card(
                  margin: EdgeInsets.zero,
                  color: color.surfaceContainerLow,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.agentDetail,
                        arguments: {'agentId': agent.id},
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.handyman_outlined,
                                size: 18,
                                color: color.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  agent.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.8,
                                    fontWeight: FontWeight.w700,
                                    color: color.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: color.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
