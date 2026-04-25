#ifndef BACKEND_H
#define BACKEND_H

#include <QObject>
#include <QProcess>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantMap>
#include <QHash>

class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY stateChanged)

public:
    explicit Backend(const QString &backendPath, QObject *parent = nullptr);
    ~Backend() override;

    QVariantMap state() const;

    Q_INVOKABLE void addTodo(const QString &title, int projectId);
    Q_INVOKABLE void deleteTodo(int todoId);
    Q_INVOKABLE void toggleTodo(int todoId);
    Q_INVOKABLE void getAppState();
    Q_INVOKABLE void sortAscending();
    Q_INVOKABLE void sortDescending();
    Q_INVOKABLE void setFilterText(const QString &text);
    Q_INVOKABLE void addProject(const QString &name);
    Q_INVOKABLE void deleteProject(int projectId);
    Q_INVOKABLE void renameProject(int projectId, const QString &newName);

signals:
    void stateChanged();

private slots:
    void onReadyRead();

private:
    void sendRequest(const QJsonObject &req);

    QProcess *m_process;
    QVariantMap m_state;
    QHash<QString, int> m_versions;
};

#endif // BACKEND_H
